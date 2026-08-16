# frozen_string_literal: true

require "rails_helper"

RSpec.describe HomeHelper, type: :helper do
  # The row vocabulary of the UI design spec §4.4. Home's system specs reach two of these
  # six states; the rest are exercised here so a wording or formatting change cannot slip
  # through, and so Task 7's pool rows inherit tested copy.
  describe "#pool_status_label" do
    def status(state, amount: 0, due_on: nil)
      instance_double(PoolStatus, state: state, amount: amount, due_on: due_on)
    end

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
end
