# frozen_string_literal: true

require "rails_helper"

# THE ADJUSTMENTS WRITER'S WIRE (computed-claims spec §3.3). `POST /adjustments` and
# `DELETE /adjustments/:id` are the purpose side's only writer besides the rules themselves, and
# three facts about them can only be asserted here rather than in the browser:
#
#   * WHOSE RULE — the id arrives on the wire, so a crafted `rule_id` is the question, and the page
#     can only ever submit an id it rendered.
#   * BOTH SIGNS — the form's two buttons decide the direction, so a signed `amount` reaching this
#     route unmediated is the contract the buttons are one spelling of.
#   * WHICH DAY "TODAY" IS — `adjustments.date` is a datetime and the day it lands on is the
#     OWNER's (§3.3: the delta lands in the period CONTAINING its date). A UTC evening is already
#     tomorrow in Tokyo and still yesterday in New York, and only a request can exercise the
#     `around_action :use_user_timezone` that makes the controller answer in the owner's zone.
RSpec.describe "Adjustments", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  # Tokyo, and the clock is frozen at a UTC evening that is ALREADY THE NEXT DAY THERE — the one
  # instant where "today" has two answers. Every date literal below is computed from it by hand.
  let(:now) { Time.utc(2026, 9, 3, 22, 0, 0) }
  let(:user) do
    create(:user, timezone: "Asia/Tokyo", period_cadence: :monthly, period_anchor_date: Date.new(2026, 1, 1))
  end
  let(:category) { create(:category, :expense, :funded, user: user, name: "Groceries") }
  let(:rule) { create(:budget, :per_period_rate, category: category, amount: 400) }

  before do
    travel_to now
    sign_in user, scope: :user
  end

  def adjust(params) = post(adjustments_path, params: params)

  describe "a top-up", :aggregate_failures do
    it "writes one positive row on the rule and comes back to the budget page" do
      adjust(rule_id: rule.id, amount: "100")

      expect(response).to redirect_to(budget_page_path)
      expect(rule.adjustments.count).to eq(1)
      expect(rule.adjustments.first.amount).to eq(100)
    end

    # A NEGATIVE AMOUNT IS THE SAME ROUTE AND THE SAME ROW (§3.3: "one table, both signs"). The
    # money column is the only one in this app with no lower bound, so this is the assertion that
    # says the absence is deliberate rather than a validation nobody wrote.
    it "writes one negative row for a take-back" do
      adjust(rule_id: rule.id, amount: "-158")

      expect(response).to redirect_to(budget_page_path)
      expect(rule.adjustments.first.amount).to eq(-158)
    end

    # THE BUTTONS' SPELLING. The form types a MAGNITUDE and the button says the direction, so
    # `amount_sign` is what a browser submission carries; the signed `amount` above is what the
    # route accepts without one. Both must land on the same row, or the two spellings are two
    # writers.
    it "takes the direction from the button that was pressed, whatever the typed sign" do
      adjust(rule_id: rule.id, amount: "158", amount_sign: "-1")

      expect(rule.adjustments.first.amount).to eq(-158)
    end
  end

  # ZERO IS THE ONE AMOUNT THAT SAYS NOTHING, and it is refused in three places — the CHECK
  # constraint, `Adjustment`'s own validation, and here as a 422 the page can render. What this
  # pins is that the refusal arrives as the RECORD's message rather than as a 500 from the
  # database or a silent redirect that wrote nothing and said so.
  describe "a zero amount", :aggregate_failures do
    it "is refused at 422 with the record's own sentence, and writes nothing" do
      adjust(rule_id: rule.id, amount: "0")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Amount must be other than 0")
      expect(rule.adjustments.count).to eq(0)
    end
  end

  # THE OWNERSHIP BOUNDARY, and it is a 404 rather than a refusal for the reason every scoped
  # lookup in this app is: a rule that is not this user's does not exist as far as this session is
  # concerned, and "refused" would confirm that the id names something real.
  describe "a rule belonging to somebody else", :aggregate_failures do
    it "is not found, and the stranger's rule gains nothing" do
      intruder = create(:budget, :per_period_rate, amount: 400)

      adjust(rule_id: intruder.id, amount: "100")

      expect(response).to have_http_status(:not_found)
      expect(intruder.adjustments.count).to eq(0)
    end
  end

  # ** THE DEFAULT DATE IS THE OWNER'S TODAY, NOT UTC'S. ** The frozen instant is Sep 3 22:00 UTC,
  # which is Sep 4 07:00 in Tokyo: the row must land in the period containing SEP 4. Both halves
  # are asserted, and the second is what makes the first mean something — the stored instant's
  # bare UTC date is Sep 3, so a `local_day` reading Sep 4 can only come from the re-zoning.
  describe "the date, left to the app", :aggregate_failures do
    it "lands on the owner's calendar day even where UTC has already turned over" do
      adjust(rule_id: rule.id, amount: "100")

      adjustment = rule.adjustments.first
      expect(adjustment.local_day).to eq(Date.new(2026, 9, 4))
      expect(adjustment.date.utc.to_date).to eq(Date.new(2026, 9, 3))
    end
  end

  # THE OTHER DIRECTION, WHICH IS THE ONE A NAIVE CAST GETS WRONG. Assigning the string
  # "2026-09-12" to a datetime column casts it at UTC midnight; re-zoned to New York that is
  # Sep 11 20:00 — the delta lands in the period BEFORE the one the user picked. Parsing it in the
  # owner's zone is what puts it on Sep 12, and only a negative offset can tell the two apart.
  describe "a date the user picked", :aggregate_failures do
    let(:user) do
      create(
        :user,
        timezone: "America/New_York",
        period_cadence: :monthly,
        period_anchor_date: Date.new(2026, 1, 1)
      )
    end

    it "is read in the owner's zone rather than at UTC midnight" do
      adjust(rule_id: rule.id, amount: "100", date: "2026-09-12")

      expect(rule.adjustments.first.local_day).to eq(Date.new(2026, 9, 12))
    end

    # A DATE THE COLUMN CANNOT HOLD IS A 422, NOT A 500. The cast answers nil and `Adjustment`'s
    # own `presence` validation refuses it — the same shape every other bad field takes, on a
    # value a hand-built request is the only way to send.
    it "is refused rather than raised when it is not a date at all", :aggregate_failures do
      adjust(rule_id: rule.id, amount: "100", date: "the twelfth")

      expect(response).to have_http_status(:unprocessable_content)
      expect(rule.adjustments.count).to eq(0)
    end
  end

  # SKIPPING IS A SERVER-COMPUTED −PLANNED (§3.3: "skip a period = an adjustment of −planned dated
  # today"). The figure is NOT carried in a hidden field, and that is the point: a page rendered
  # before another delta landed would skip the wrong amount, and the planned share is a fact the
  # calculator owns.
  #
  # THE FIXTURE'S ARITHMETIC, BY HAND: a $1,200 target on the category and a $150-a-period rule
  # born Aug 1, on a monthly grid anchored Jan 1 — so the walk visits August and September (accrual
  # starts at the later of `funded_since` and the rule's own birth). August plans `min($150,
  # $1,200 − $0)` = $150 and September plans `min($150, $1,200 − $150)` = $150.
  describe "skipping a period", :aggregate_failures do
    let(:goal) { create(:category, :expense, :funded, user: user, name: "Vacation", target_amount: 1_200) }
    let(:target_rule) do
      create(:budget, :per_period_rate, category: goal, amount: 150, created_at: Time.utc(2026, 8, 1))
    end

    it "writes exactly minus this period's planned share, dated the owner's today" do
      adjust(rule_id: target_rule.id, skip: "1")

      expect(response).to redirect_to(budget_page_path)
      expect(target_rule.adjustments.first.amount).to eq(-150)
      expect(target_rule.adjustments.first.local_day).to eq(Date.new(2026, 9, 4))
    end

    # A PERIOD WITH NOTHING PLANNED HAS NOTHING TO SKIP, and the model's own refusal is the backstop
    # for a button the page hides. Asserted rather than assumed, because "skip" is the one door
    # whose amount the user never types.
    #
    # A $1,050 top-up dated Aug 15 takes August to `min($0 + $150 + $1,050, $1,200)` = the target,
    # so September's gap is $0 and its planned share is $0 — a fund that is already full plans
    # nothing, and a skip there would be a zero row.
    it "is refused where the period plans nothing, rather than writing a zero" do
      create(:adjustment, rule: target_rule, amount: 1_050, date: Time.utc(2026, 8, 15))

      adjust(rule_id: target_rule.id, skip: "1")

      expect(response).to have_http_status(:unprocessable_content)
      expect(target_rule.adjustments.count).to eq(1)
    end
  end

  # DELETE IS SCOPED THROUGH THE RULE, because `adjustments` carries no user column — the row's
  # owner is its rule's owner and there is exactly one place that walk is spelled.
  describe "removing one", :aggregate_failures do
    it "deletes the user's own row and comes back to the budget page" do
      adjustment = create(:adjustment, rule: rule, amount: 100, date: now)

      delete(adjustment_path(adjustment))

      expect(response).to redirect_to(budget_page_path)
      expect(Adjustment.where(id: adjustment.id)).to be_empty
    end

    it "cannot delete a row on somebody else's rule" do
      stranger = create(:adjustment, amount: 100, date: now)

      delete(adjustment_path(stranger))

      expect(response).to have_http_status(:not_found)
      expect(Adjustment.where(id: stranger.id)).to be_present
    end
  end

  describe "a signed-out request", :aggregate_failures do
    it "is sent to sign in rather than writing anything" do
      sign_out user

      adjust(rule_id: rule.id, amount: "100")

      expect(response).to redirect_to(new_user_session_path)
      expect(rule.adjustments.count).to eq(0)
    end
  end
end
