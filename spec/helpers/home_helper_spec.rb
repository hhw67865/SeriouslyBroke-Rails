# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper, type: :helper do
  # `needs_attention?` is answered from PoolStatus's own constant rather than a hand-set
  # flag, so a double can never claim a combination the real object cannot produce.
  def status(state, amount: 0, due_on: nil)
    instance_double(
      PoolStatus,
      state: state,
      amount: amount,
      due_on: due_on,
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
