# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper, type: :helper do
  # `needs_attention?` is answered from HoldingStatus's own constant rather than a hand-set
  # flag, so a double can never claim a combination the real object cannot produce.
  #
  # `period_closed?` is on the double because #pool_problem_label now READS it off the status
  # rather than taking it as a keyword — that is the fix, not an accident of the double: a keyword
  # gave a caller the option of omitting it, and the attention band took that option.
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

  # ── THE ORPHAN ARM IS DELETED (Task 6), and with it four examples: "says an unassigned pool
  # cannot be funded at all", "keeps the status when an unassigned pool is also in trouble", "keeps
  # a due date when an unassigned pool is also overdue", and "says nothing new about a pool that has
  # an account" (which passed `orphan: false` to say so). A category belongs to no account and needs
  # none — allocating money moves nothing physical (two-ledger spec §2) — so "no account — nothing
  # can fund it" describes no state the app can be in.
  #
  # WHAT THE METHOD IS FOR SURVIVES WHOLE and is what the rest of this describe pins: it FORCES
  # `period_closed:` off the status rather than accepting it as a keyword, so no caller of Home's
  # attention band can omit the suffix the categories band prints inches below.
  describe "#pool_problem_label" do
    it "defaults to the plain status label" do
      expect(helper.pool_problem_label(status(:wont_make_it, due_on: Date.new(2026, 2, 14))))
        .to eq("won't make it · Feb 14")
    end

    # THE DEFECT THIS METHOD SHIPPED WITH, in the exact figures it shipped in. It passed
    # `changed_after_distributing:` and NOT `period_closed:`, so ONE Home render printed
    # `overdrawn $80.00 · last period` in the categories band and `overdrawn $80.00` in the attention
    # band a few inches above — two bands disagreeing about one category on one screen.
    #
    # Asserted as full equality against the same literal `#pool_status_label`'s own closed-period
    # example uses, so the two methods are pinned to one string rather than to each other.
    it "carries the closed-period suffix the categories band prints" do
      label = helper.pool_problem_label(status(:overdrawn, amount: 80, period_closed: true))

      expect(label).to eq("overdrawn $80.00 · last period")
    end

    # The other direction, and the one that keeps the suffix meaning something: same state, same
    # amount, same method — the flag is the only variable, so a suffix printed unconditionally
    # fails here.
    it "stays silent about a period that has not closed" do
      expect(helper.pool_problem_label(status(:overdrawn, amount: 80))).to eq("overdrawn $80.00")
    end

    # BOTH SUFFIXES AT ONCE, in the order `#pool_status_label` fixes: how the category is doing,
    # which period its money belongs to, then why.
    it "carries both suffixes together" do
      label = helper.pool_problem_label(
        status(:behind, amount: 50, period_closed: true),
        changed_after_distributing: true
      )

      expect(label).to eq("behind $50.00 · last period — you changed a rule here after distributing")
    end
  end
end
