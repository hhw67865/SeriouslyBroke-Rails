# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper, type: :helper do
  # `needs_attention?` is answered from HoldingStatus's own constant rather than a hand-set
  # flag, so a double can never claim a combination the real object cannot produce.
  #
  # `period_closed?` is on the double because #period_row_clause READS it off the status rather than
  # taking it as a keyword — that is the fix, not an accident of the double: a keyword gave a caller
  # the option of omitting it, and Home's attention band took that option.
  def status(state, amount: 0, due_on: nil, target: nil, period_closed: false)
    instance_double(
      HoldingStatus,
      state: state,
      amount: amount,
      due_on: due_on,
      target: target,
      period_closed?: period_closed,
      needs_attention?: HoldingStatus::ATTENTION_STATES.include?(state)
    )
  end

  # The row vocabulary of the UI design spec §4.4. Home's system specs reach two of these
  # six states; the rest are exercised here so a wording or formatting change cannot slip
  # through, and so Task 7's pool rows inherit tested copy.
  describe "#pool_status_label" do
    it "names the amount already spent when overdrawn" do
      expect(helper.pool_status_label(status(:overdrawn, amount: 50))).to eq("overdrawn $50.00")
    end

    it "names the date that passed when overdue" do
      label = helper.pool_status_label(status(:overdue, amount: 600, due_on: Date.new(2026, 3, 1)))

      expect(label).to eq("overdue · was Mar 1")
    end

    it "names the unreachable date when it won't make it" do
      label = helper.pool_status_label(status(:wont_make_it, amount: 300, due_on: Date.new(2026, 2, 14)))

      expect(label).to eq("won't make it · Feb 14")
    end

    # How much EXTRA is owed, not the gap to target — the two differ and the spec is explicit.
    it "names the catch-up amount when behind" do
      expect(helper.pool_status_label(status(:behind, amount: 385))).to eq("behind $385.00")
    end

    # The only state that renders a spendable number, because a rate envelope is the only
    # kind where the balance genuinely is spendable (principle 2).
    it "names what is left to spend on a rate envelope" do
      expect(helper.pool_status_label(status(:left_to_spend, amount: 240))).to eq("$240.00 left")
    end

    # The seventh state. Both forms read as accumulation; neither reads as money to spend,
    # which is the whole reason it exists (principle 2).
    it "names progress toward a target when saving" do
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 2_400)))
        .to eq("$424.00 of $2,400.00")
    end

    it "names what has been put away when a savings pool has no target" do
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 0))).to eq("$424.00 saved")
    end

    # The word this state was carved out to avoid, asserted directly: a substring check on
    # "$424.00" alone would pass against the label it replaced.
    it "never says a savings balance is left to spend", :aggregate_failures do
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 2_400))).not_to include("left")
      expect(helper.pool_status_label(status(:saving, amount: 424, target: 0))).not_to include("left")
    end

    it "stays quiet on track" do
      expect(helper.pool_status_label(status(:on_track, amount: 1_000))).to eq("$1,000.00 · on track")
    end

    # Single-digit days unpadded: the locale's :short format renders "Mar 01", which is not
    # the vocabulary the spec writes and not how any other date in this app is formatted.
    it "does not zero-pad a single-digit day" do
      label = helper.pool_status_label(status(:overdue, amount: 10, due_on: Date.new(2026, 3, 5)))

      expect(label).to eq("overdue · was Mar 5")
    end

    # Plan 2b decision 1: the closed-period marker is a SUFFIX on the real balance, never a
    # replacement for it. The $60 is physically in the envelope until a distribution moves it,
    # and `Σ pools == your bank balance` is the invariant the whole app rests on — so the
    # figure has to survive the marker. Asserted as full equality, because a `have_content`
    # on the suffix alone would pass against a label that had dropped the amount.
    it "marks a closed period without touching the amount" do
      label = helper.pool_status_label(status(:left_to_spend, amount: 60), period_closed: true)

      expect(label).to eq("$60.00 left · last period")
    end

    # The default, and the direction that keeps the marker meaning something: an ordinary row
    # must not carry it. Same state and same amount as above, so the flag is the only variable.
    it "says nothing about a period that has not closed" do
      expect(helper.pool_status_label(status(:left_to_spend, amount: 60))).to eq("$60.00 left")
    end

    # A closed period is a fact about the money, not about how the pool is doing, so it does
    # not displace the state's own wording — an overdrawn envelope whose period ended is both
    # at once. This is the pair that would fail if the suffix were folded into one branch.
    it "marks a closed period on a state that is already in trouble" do
      label = helper.pool_status_label(status(:overdrawn, amount: 80), period_closed: true)

      expect(label).to eq("overdrawn $80.00 · last period")
    end
  end

  # What an expanded row calls each rule. An item names itself; an item-less rule used to
  # render the literal word "Rule", which on screen reads as missing data rather than as
  # information. The row already prints the amount and the date on the other side, so what is
  # missing from the line is the rule's SHAPE — how often it comes round.
  describe "#pool_rule_label" do
    it "uses the item's name when the rule has one" do
      budget = build(:budget, item: build(:item, name: "Electric Bill"), anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Electric Bill")
    end

    it "names a monthly rule by its cadence" do
      budget = build(:budget, interval_months: 1, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Monthly")
    end

    it "names a multi-month rule by its interval" do
      budget = build(:budget, interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Every 6 months")
    end

    it "names a rule that never rolls a one-off" do
      budget = build(:budget, :one_time, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("One-off")
    end

    # A per-period rule carries no anchor, so no expanded row can reach it today — but it is
    # the one shape whose blank interval does NOT mean "never rolls", and reading it as a
    # one-off would be silently wrong the day something asks.
    it "names a per-period rule by its cadence, not as a one-off" do
      budget = build(:budget, :per_period_rate)

      expect(helper.pool_rule_label(budget)).to eq("Per period")
    end
  end

  # ── `#pool_problem_label` IS DELETED (answers-first Task 2) and its four examples with it: "defaults
  # to the plain status label", "carries the closed-period suffix the categories band prints", "stays
  # silent about a period that has not closed" and "carries both suffixes together". (Its orphan arm
  # had already gone in two-ledger Task 6, taking four more.)
  #
  # THE PROPERTY IT PINNED IS NOT LOST — IT BECAME STRUCTURAL. The method forced `period_closed:` off
  # the status so that Home's attention band could not omit the suffix the categories band printed
  # inches below. The trouble strip that replaced that band renders `shared/_holding_status`, which
  # threads BOTH suffixes off ONE `HomePresenter::Row`: a caller chooses which OBJECT to pass, not
  # which suffixes, and an object missing an answer raises at render. The two suffixes' own wording
  # is pinned above, on `#pool_status_label`, which is where it always lived. Seven examples replace
  # the four.

  # THE SMALL CLAUSE AFTER A "THIS PERIOD" BAR (answers-first spec §4). Home's system specs reach the
  # attention arm and the two silent states; every arm is pinned here so the decision about what
  # "earns its place" cannot drift silently.
  describe "#period_row_clause" do
    # A double rather than a real `PeriodRow`, for the reason the `status` double above exists: this
    # method reads exactly three questions off the row and a real one would drag a category, a
    # calculator and a period window in to answer them.
    def period_row(state, amount: 0, due_on: nil, period_closed: false, changed: false)
      instance_double(
        HomePresenter::PeriodRow,
        status: status(state, amount: amount, due_on: due_on, period_closed: period_closed),
        needs_attention?: HoldingStatus::ATTENTION_STATES.include?(state),
        changed_after_distributing?: changed
      )
    end

    # THE BAR HAS ALREADY SAID IT. `$90.00 left` is the $310-of-$400 row's own remainder and
    # `$424.00 of $2,400.00` is the goal bar's own two figures, so a clause here would be the screen
    # answering one question twice in two denominations.
    it "says nothing on a category that is simply left to spend" do
      expect(helper.period_row_clause(period_row(:left_to_spend, amount: 90))).to be_nil
    end

    it "says nothing on a savings goal" do
      expect(helper.period_row_clause(period_row(:saving, amount: 424))).to be_nil
    end

    # THE ONE THING A BAR-SILENT ROW STILL HAS TO SAY. Which period the money belongs to is a fact
    # about the MONEY rather than about how the category is doing, and the bar cannot carry it — a
    # row silent about it is a user surprised by the next distribution taking $400 back. It is also
    # what /budget prints for the same category on the same afternoon.
    it "still marks a closed period on an otherwise silent row" do
      expect(helper.period_row_clause(period_row(:left_to_spend, amount: 400, period_closed: true)))
        .to eq("last period")
    end

    # THE WORD WITHOUT THE MONEY. `pool_state_label` would print `$2,000.00 · on track`, and that
    # amount is the HOLDING while the bar beside it is the SPENDING — two money figures from two
    # different questions, an inch apart.
    it "keeps on track as a word and drops its amount" do
      expect(helper.period_row_clause(period_row(:on_track, amount: 2_000))).to eq("on track")
    end

    # THE DATE RIDES ON THE QUIET ARM, which is `HomePresenter::Row#due_marker?`'s rule re-housed.
    it "dates a quiet row when its rule has a due date" do
      row = period_row(:on_track, amount: 2_000, due_on: Date.new(2026, 10, 17))

      expect(helper.period_row_clause(row)).to eq("on track · Oct 17")
    end

    # THE OTHER DIRECTION OF THE SAME GATE: an attention row has already printed its date inside the
    # label, and `overdrawn $50.00 · Oct 17` would date a debt with a deadline belonging to something
    # else.
    it "leaves the date off a row that needs attention" do
      row = period_row(:overdrawn, amount: 50, due_on: Date.new(2026, 10, 17))

      expect(helper.period_row_clause(row)).to eq("overdrawn $50.00")
    end

    # BOTH SUFFIXES AT ONCE, in the order `#pool_status_label` fixes: how the category is doing,
    # which period its money belongs to, then why. Asserted as full equality against the same literal
    # that method's own example uses, so the two are pinned to one string rather than to each other.
    it "carries both suffixes on a row that needs attention" do
      row = period_row(:behind, amount: 50, period_closed: true, changed: true)

      expect(helper.period_row_clause(row))
        .to eq("behind $50.00 · last period — you changed a rule here after distributing")
    end
  end
end
