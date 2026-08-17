# frozen_string_literal: true

require "rails_helper"

# THE LEDGER-SHARING SEAM, which is not any one class's subject and so is not any one class's spec.
#
# Three classes take part: PoolBalanceLedger owns the rule (#for_as_of!), AllocationCalculator
# shares one with another fill of itself through a `protected` writer, and ReallocationPresenter
# accepts one from HomePresenter through a documented keyword. What is pinned here is the SEAM —
# who may hand a ledger to whom, and what happens when the two are about different moments. What
# each class MEANS is measured where it always was: pool_balance_ledger_spec for the terms,
# allocation_calculator_spec for the fill, allocation_committer_spec for the write. Restating any
# of that here would be a second reader of the same rules, which is the defect this branch polices.
#
# BOTH DIRECTIONS FOR EVERY GUARD. A raise asserted only where it fires is satisfied by a method
# that raises always, and this branch has found that shape before — so every example below has a
# twin asserting the guard stays out of the way.
RSpec.describe "ledger sharing", type: :model do
  let(:user) { create(:user, :biweekly) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:groceries) { create(:pool, user: user, name: "Groceries", account: checking, priority: 1) }
  let(:today) { Date.new(2026, 8, 20) }
  let(:bound) { Date.new(2026, 8, 1) }

  def unbounded = PoolBalanceLedger.new([checking, groceries])
  def bounded = PoolBalanceLedger.new([checking, groceries], as_of: bound)

  # Every SQL statement a block issued, so "no second ledger was built" is read off the database
  # rather than off the source. Same helper shape as pool_balance_ledger_spec's.
  def sql_for(&block)
    statements = []
    recorder = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] unless ["SCHEMA", "TRANSACTION"].include?(payload[:name])
    end
    ActiveSupport::Notifications.subscribed(recorder, "sql.active_record", &block)
    statements
  end

  describe "PoolBalanceLedger#for_as_of!" do
    it "hands back the ledger itself when the bounds agree" do
      ledger = unbounded

      expect(ledger.for_as_of!(nil)).to equal(ledger)
    end

    # The bounded pair, so the match is asserted at a real date and not only at nil — a guard that
    # only ever compares nil to nil would pass while comparing the wrong two things.
    it "hands back a bounded ledger to a caller asking about the same bound" do
      ledger = bounded

      expect(ledger.for_as_of!(bound)).to equal(ledger)
    end

    it "refuses a bounded ledger to a caller reading the ledger as it stands" do
      expect { bounded.for_as_of!(nil) }
        .to raise_error(PoolBalanceLedger::AsOfMismatch, /one ledger per `as_of`/)
    end

    it "refuses an unbounded ledger to a caller asking about an earlier moment" do
      expect { unbounded.for_as_of!(bound) }
        .to raise_error(PoolBalanceLedger::AsOfMismatch, /one ledger per `as_of`/)
    end

    # The message is the whole value of the raise: two `as_of`s and the rule that relates them.
    it "names both moments in the message" do
      expect { bounded.for_as_of!(nil) }
        .to raise_error(PoolBalanceLedger::AsOfMismatch, /#{Regexp.escape(bound.inspect)}.*nil/m)
    end
  end

  describe "AllocationCalculator#with_overrides" do
    let(:proposal) { AllocationCalculator.new(user: user, account: checking, today: today) }

    before { groceries }

    it "carries the same ledger object rather than building a second one" do
      twin = proposal.with_overrides({})

      expect(twin.send(:ledger)).to equal(proposal.send(:ledger))
    end

    # The cost half, measured rather than inferred: the twin runs the fill without any grouped
    # aggregate of its own, because the ones it needs have already been memoised on the shared
    # ledger. `sum_amount` is the alias every grouped term in PoolBalanceLedger#compute carries.
    it "runs no grouped term of its own once the sharer has read them" do
      proposal.rows
      twin = proposal.with_overrides({})

      grouped = sql_for { twin.rows }.grep(/sum_amount|maximum_date/)

      expect(grouped).to be_empty
    end

    it "keeps the user, the account and the day of the proposal it came from", :aggregate_failures do
      twin = proposal.with_overrides({ groceries.id.to_s => "40" })

      expect([twin.user, twin.account, twin.today]).to eq([user, checking, today])
      expect(twin.overrides).to eq({ groceries.id.to_s => 40.to_d })
    end

    # THE SURFACE THAT IS CLOSED. A `ledger:` keyword here would have offered every caller in the
    # app the one thing the committer mutation proved dangerous — a ledger from before a write —
    # so there is no keyword, and `#share_ledger` is protected. Both halves are asserted, because
    # "protected" is a claim about a method table that a later edit can quietly withdraw.
    it "cannot be supplied a ledger through the constructor" do
      expect { AllocationCalculator.new(user: user, account: checking, today: today, ledger: unbounded) }
        .to raise_error(ArgumentError, /unknown keyword: :ledger/)
    end

    it "cannot be handed a ledger by anything that is not an AllocationCalculator" do
      expect { proposal.share_ledger(unbounded) }
        .to raise_error(NoMethodError, /protected method .share_ledger/)
    end

    # And the receiver test is not vacuous — the protected call SUCCEEDS between two instances of
    # the class, which is what #with_overrides does one line down from the refusal above. Two
    # proposals built independently hold different ledgers until one is shared.
    it "may be handed one by another AllocationCalculator", :aggregate_failures do
      other = AllocationCalculator.new(user: user, account: checking, today: today)

      expect(other.send(:ledger)).not_to equal(proposal.send(:ledger))
      expect { other.send(:share_ledger, proposal.send(:ledger)) }.not_to raise_error
      expect(other.send(:ledger)).to equal(proposal.send(:ledger))
    end
  end

  describe "ReallocationPresenter's ledger keyword" do
    before { groceries }

    it "uses the ledger it was given rather than building one" do
      ledger = unbounded
      presenter = ReallocationPresenter.new(user: user, to_pool: groceries, today: today, ledger: ledger)

      expect(presenter.send(:ledger)).to equal(ledger)
    end

    it "builds its own when it is given none" do
      presenter = ReallocationPresenter.new(user: user, to_pool: groceries, today: today)

      expect(presenter.send(:ledger)).to be_a(PoolBalanceLedger)
    end

    # The guard fires at CONSTRUCTION rather than at first read, so a screen holding a ledger from
    # another moment fails before it can render a figure from it.
    it "refuses a ledger bounded at another moment, at construction" do
      expect { ReallocationPresenter.new(user: user, to_pool: groceries, today: today, ledger: bounded) }
        .to raise_error(PoolBalanceLedger::AsOfMismatch, /one ledger per `as_of`/)
    end

    # HomePresenter's own ledger is unbounded, which is the pair this guard has to let through.
    it "accepts the unbounded ledger Home actually hands it" do
      home = HomePresenter.new(user: user, today: today)

      expect { ReallocationPresenter.new(user: user, to_pool: groceries, today: today, ledger: home.send(:ledger)) }
        .not_to raise_error
    end
  end
end
