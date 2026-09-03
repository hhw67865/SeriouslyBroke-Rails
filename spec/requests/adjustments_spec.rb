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
  # "2026-09-02" to a datetime column casts it at UTC midnight; re-zoned to New York that is
  # Sep 1 20:00 — the delta lands on the day BEFORE the one the user picked. Parsing it in the
  # owner's zone is what puts it on Sep 2, and only a negative offset can tell the two apart.
  #
  # THE DAY IS SEP 2 AND NOT SEP 12 (fix round MED-1). The frozen instant is Sep 3 18:00 in New
  # York, so Sep 12 is a week in this user's future and is now refused before its zone is ever the
  # question — a date the walk has not reached counts toward nothing. Sep 2 sits one day inside the
  # span and exercises the same UTC-midnight cast the original literal did.
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
      adjust(rule_id: rule.id, amount: "100", date: "2026-09-02")

      expect(rule.adjustments.sole.local_day).to eq(Date.new(2026, 9, 2))
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

  # ** A DATE THE RULE CANNOT COUNT IS REFUSED (fix round MED-1). ** `accrued(P) = planned(P) + Σ
  # adjustments dated inside P` sums only over the periods the walk VISITS, so a row dated outside
  # that span moves no figure on any screen: it is written, invisible in the row's list (which
  # shows this period), and therefore unremovable. A 302 and a success flash over a claim that
  # never moved is the worst of the three possible answers, and this group is what forbids it.
  #
  # THE SPAN IS `ClaimCalculator#countable_span` — the walk's own first day through today, in the
  # OWNER's zone. Every literal below is computed by hand from the frozen instant: Sep 3 22:00 UTC
  # is Sep 4 07:00 in Tokyo, so the owner's today is SEP 4 and the monthly period anchored Jan 1
  # runs Sep 1 – Sep 30.
  describe "a date the rule cannot count" do
    # A RATE RULE COUNTS THIS PERIOD ONLY (§3.1: use-it-or-lose-it, nothing carries), so the walk
    # visits one period and August is outside it — the row would sum into nothing.
    it "refuses a past period on a rate rule, and names the span in the user's words", :aggregate_failures do
      adjust(rule_id: rule.id, amount: "100", date: "2026-08-20")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Groceries counts this period only, up to today")
      expect(response.body).to include("pick a date between Sep 1 and Sep 4")
      expect(rule.adjustments.count).to eq(0)
    end

    # THE FIRST DAY OF THE SPAN IS INSIDE IT, and this is the half that stops the guard from being
    # satisfied by a class that refuses everything.
    it "accepts the first day of the current period on a rate rule", :aggregate_failures do
      adjust(rule_id: rule.id, amount: "100", date: "2026-09-01")

      expect(response).to redirect_to(budget_page_path)
      expect(rule.adjustments.sole.local_day).to eq(Date.new(2026, 9, 1))
    end

    # ** TOMORROW IS REFUSED TOO, AND THE OWNER'S ZONE IS WHAT DECIDES WHICH DAY THAT IS. ** Sep 5
    # is still inside the period Sep 1 – Sep 30, so a bound taken from the period alone would let
    # this through; the walk stops at the period containing TODAY, and money moved on a day that
    # has not happened is not money this claim has.
    it "refuses tomorrow in the owner's zone even though it is inside the period", :aggregate_failures do
      adjust(rule_id: rule.id, amount: "100", date: "2026-09-05")

      expect(response).to have_http_status(:unprocessable_content)
      expect(rule.adjustments.count).to eq(0)
    end

    # AN ACCRUING RULE REACHES BACK TO ITS OWN BIRTH AND NO FURTHER (§3.2: "never retroactively";
    # the accrual start is the later of the category's funding date and the rule's own creation).
    # The rule below was born Aug 1, so July is before the walk opens.
    describe "on a fund that has been building since Aug 1" do
      let(:goal) { create(:category, :expense, :funded, user: user, name: "Vacation", target_amount: 1_200) }
      let(:target_rule) do
        create(:budget, :per_period_rate, category: goal, amount: 150, created_at: Time.utc(2026, 8, 1, 9))
      end

      it "refuses a date before it started building", :aggregate_failures do
        adjust(rule_id: target_rule.id, amount: "100", date: "2026-07-31")

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Vacation counts dates from when it started building")
        expect(response.body).to include("pick a date between Aug 1 and Sep 4")
        expect(target_rule.adjustments.count).to eq(0)
      end

      # THE OTHER SIDE OF THE SAME BOUNDARY, one day later: a fund reaches back further than a rate
      # rule does, and this is what says the span is read off the RULE rather than off the period.
      it "accepts the day it started building" do
        adjust(rule_id: target_rule.id, amount: "100", date: "2026-08-01")

        expect(target_rule.adjustments.sole.local_day).to eq(Date.new(2026, 8, 1))
      end
    end
  end

  # SKIPPING IS A SERVER-COMPUTED −ACCRUED (§3.3: "skip a period = an adjustment of −planned dated
  # today", read as the ruling of the fix round states it — the skip's job is to leave the period
  # accruing NOTHING). The figure is NOT carried in a hidden field, and that is the point: a page
  # rendered before another delta landed would skip the wrong amount, and the share is a fact the
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

    # ** A SECOND SKIP MUST NOT BE A RAID WEARING THE SKIP'S WORDS (fix round MED-2). **
    # `planned_this_period` is PRE-adjustment, so −planned on a period already carrying a +$50
    # top-up leaves $50 still accruing — and on a period already skipped it would take another
    # −$150 out of the fund's prior savings under a flash that says "skipped". The amount is
    # whatever lands `accrued_this_period` at exactly zero: −($150 planned + $50 topped up) = −$200.
    it "writes minus the whole accrual, not minus the plan, when a top-up is already there", :aggregate_failures do
      create(:adjustment, rule: target_rule, amount: 50, date: Time.utc(2026, 9, 2, 12))

      adjust(rule_id: target_rule.id, skip: "1")

      # BY VALUE AND NOT BY `created_at`: the clock is frozen, so both rows carry the same instant
      # and "the last one written" is not a question the column can answer.
      expect(target_rule.adjustments.pluck(:amount)).to contain_exactly(50, -200)
      expect(target_rule.reload.claim_calculator(today: Date.new(2026, 9, 4)).accrued_this_period).to eq(0)
    end

    # A PERIOD WITH NOTHING LEFT TO ACCRUE HAS NOTHING TO SKIP, and the model's own refusal is the
    # backstop for a button the page hides. Asserted rather than assumed, because "skip" is the one
    # door whose amount the user never types.
    #
    # A $1,050 top-up dated Aug 15 takes August to `min($0 + $150 + $1,050, $1,200)` = the target,
    # so September's gap is $0 and its planned share is $0 — a fund that is already full plans
    # nothing, and a skip there would be a zero row.
    it "is refused where the period plans nothing, rather than writing a zero" do
      create(:adjustment, rule: target_rule, amount: 1_050, date: Time.utc(2026, 8, 15))

      adjust(rule_id: target_rule.id, skip: "1")

      expect(response).to have_http_status(:unprocessable_content)
      expect(target_rule.adjustments.count).to eq(1)
      # THE SENTENCE IS THE SKIP'S OWN, not "Amount must be other than 0" — the amount is the
      # SERVER's, so the record's honest complaint about it names a figure the user never typed
      # and cannot act on.
      expect(response.body).to include("Vacation isn&#39;t accruing anything this period")
    end

    # THE SAME REFUSAL FROM THE OTHER SIDE: the plan is $150 and a −$150 is already dated inside
    # the period, so the accrual is zero and a second skip would write another zero row. This is
    # the shape the pre-adjustment reading got wrong — there it would have written −$150 again.
    it "is refused where the period has already been skipped", :aggregate_failures do
      create(:adjustment, rule: target_rule, amount: -150, date: Time.utc(2026, 9, 2, 12))

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

    # ** THE FLASH SAYS WHAT WAS REMOVED IN THE SAME FIVE WORDS THAT WROTE IT (fix round LOW-2). **
    # The amount is a MAGNITUDE and the direction is a word, exactly as it is on the four writing
    # flashes — `number_to_currency` of a signed row printed "Removed -$150.00 from Vacation", a
    # minus sign doing the work of a verb on the one screen where the user has just pressed
    # "Remove".
    it "names the direction of a removed take-back rather than printing a minus", :aggregate_failures do
      goal = create(:category, :expense, :funded, user: user, name: "Vacation", target_amount: 1_200)
      goal_rule = create(:budget, :per_period_rate, category: goal, amount: 150)
      adjustment = create(:adjustment, rule: goal_rule, amount: -150, date: now)

      delete(adjustment_path(adjustment))

      expect(flash[:notice]).to eq("Removed the $150.00 taken back from Vacation.")
    end

    # The positive half, on the other shape, so a sentence built from the sign alone would fail one
    # of the two.
    it "names a removed top-up on a rate rule" do
      adjustment = create(:adjustment, rule: rule, amount: 50, date: now)

      delete(adjustment_path(adjustment))

      expect(flash[:notice]).to eq("Removed the $50.00 top-up on Groceries.")
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
