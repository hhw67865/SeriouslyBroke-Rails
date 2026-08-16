# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper, type: :helper do
  # `needs_attention?` is answered from PoolStatus's own constant rather than a hand-set
  # flag, so a double can never claim a combination the real object cannot produce.
  def status(state, amount: 0, due_on: nil, target: nil)
    instance_double(
      PoolStatus,
      state: state,
      amount: amount,
      due_on: due_on,
      target: target,
      needs_attention?: PoolStatus::ATTENTION_STATES.include?(state)
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
  end

  # What an expanded row calls each rule. An item names itself; an item-less rule used to
  # render the literal word "Rule", which on screen reads as missing data rather than as
  # information. The row already prints the amount and the date on the other side, so what is
  # missing from the line is the rule's SHAPE — how often it comes round.
  describe "#pool_rule_label" do
    it "uses the item's name when the rule has one" do
      budget = build(:pool_budget, item: build(:item, name: "Electric Bill"), anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Electric Bill")
    end

    it "names a monthly rule by its cadence" do
      budget = build(:pool_budget, interval_months: 1, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Monthly")
    end

    it "names a multi-month rule by its interval" do
      budget = build(:pool_budget, interval_months: 6, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("Every 6 months")
    end

    it "names a rule that never rolls a one-off" do
      budget = build(:pool_budget, :one_time, anchor_date: Date.new(2026, 3, 1))

      expect(helper.pool_rule_label(budget)).to eq("One-off")
    end

    # A per-period rule carries no anchor, so no expanded row can reach it today — but it is
    # the one shape whose blank interval does NOT mean "never rolls", and reading it as a
    # one-off would be silently wrong the day something asks.
    it "names a per-period rule by its cadence, not as a one-off" do
      budget = build(:pool_budget, :per_paycheck_rate)

      expect(helper.pool_rule_label(budget)).to eq("Per period")
    end
  end

  # A pool belonging to no account is in trouble for a reason PoolStatus does not model, so
  # this is the only wording that does not come from #state. Every branch is on screen today:
  # the seeds' savings pools are account-less, and an account-less pool can also be overdrawn.
  describe "#pool_problem_label" do
    it "says nothing new about a pool that has an account" do
      expect(helper.pool_problem_label(status(:behind, amount: 385), orphan: false))
        .to eq("behind $385.00")
    end

    it "defaults to the plain status label" do
      expect(helper.pool_problem_label(status(:wont_make_it, due_on: Date.new(2026, 2, 14))))
        .to eq("won't make it · Feb 14")
    end

    it "says an unassigned pool cannot be funded at all" do
      expect(helper.pool_problem_label(status(:left_to_spend, amount: 240), orphan: true))
        .to eq("no account — nothing can fund it")
    end

    # Both facts, not the louder one: unassigned is the fix, overdrawn is the damage.
    it "keeps the status when an unassigned pool is also in trouble" do
      expect(helper.pool_problem_label(status(:overdrawn, amount: 869), orphan: true))
        .to eq("no account · overdrawn $869.00")
    end

    it "keeps a due date when an unassigned pool is also overdue" do
      expect(helper.pool_problem_label(status(:overdue, amount: 600, due_on: Date.new(2026, 3, 1)), orphan: true))
        .to eq("no account · overdue · was Mar 1")
    end
  end
end
