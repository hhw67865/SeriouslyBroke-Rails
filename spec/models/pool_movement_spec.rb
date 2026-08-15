# frozen_string_literal: true

require "rails_helper"

RSpec.describe PoolMovement, type: :model do
  let(:user) { create(:user) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:groceries) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }
  let(:car) { create(:pool, :budget_pool, user: user, account: checking, name: "Car") }

  describe "associations" do
    it { is_expected.to belong_to(:from_pool).class_name("Pool") }
    it { is_expected.to belong_to(:to_pool).class_name("Pool") }
    it { is_expected.to belong_to(:source_entry).class_name("Entry").optional }
  end

  describe "factory" do
    it "builds a valid movement" do
      expect(build(:pool_movement)).to be_valid
    end

    it "creates a movement between two pools of one user", :aggregate_failures do
      movement = create(:pool_movement)

      expect(movement).to be_persisted
      expect(movement.to_pool.account).to eq(movement.from_pool)
      expect(movement.to_pool.user).to eq(movement.from_pool.user)
    end
  end

  describe "validations" do
    it "accepts a positive amount between two pools of the same user" do
      expect(build(:pool_movement, from_pool: checking, to_pool: groceries, amount: 25.00)).to be_valid
    end

    it "requires a positive amount", :aggregate_failures do
      movement = build(:pool_movement, from_pool: checking, to_pool: groceries, amount: 0)

      expect(movement).not_to be_valid
      expect(movement.errors[:amount]).to include("must be greater than 0")
    end

    it "requires a date", :aggregate_failures do
      movement = build(:pool_movement, from_pool: checking, to_pool: groceries, date: nil)

      expect(movement).not_to be_valid
      expect(movement.errors[:date]).to include("can't be blank")
    end

    it "rejects a movement to the same pool", :aggregate_failures do
      movement = build(:pool_movement, from_pool: checking, to_pool: checking)

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must differ from the source pool")
    end

    it "allows a movement between two distinct pools", :aggregate_failures do
      movement = build(:pool_movement, from_pool: groceries, to_pool: car)

      expect(movement).to be_valid
      expect(movement.errors[:to_pool]).to be_empty
    end

    it "rejects a movement between two users' pools", :aggregate_failures do
      movement = build(:pool_movement, from_pool: checking, to_pool: create(:pool, :account))

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must belong to the same user")
    end

    it "allows a movement between two accounts owned by the same user", :aggregate_failures do
      movement = build(:pool_movement, from_pool: checking, to_pool: create(:pool, :account, user: user))

      expect(movement).to be_valid
      expect(movement.errors[:to_pool]).to be_empty
    end

    # Unsaved pools carry a nil id and a nil user_id, so an id comparison reads
    # `nil == nil` and waves the record through. The pools themselves must decide.
    it "rejects a movement to the same unsaved pool", :aggregate_failures do
      pool = build(:pool, :account)
      movement = build(:pool_movement, from_pool: pool, to_pool: pool)

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must differ from the source pool")
    end

    it "rejects a movement between two unsaved pools of different users", :aggregate_failures do
      from_pool = build(:pool, :account, user: build(:user))
      to_pool = build(:pool, :account, user: build(:user))
      movement = build(:pool_movement, from_pool: from_pool, to_pool: to_pool)

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must belong to the same user")
    end

    it "allows a movement between two unsaved pools of one user" do
      unsaved_user = build(:user)
      from_pool = build(:pool, :account, user: unsaved_user)
      to_pool = build(:pool, :budget_pool, user: unsaved_user, account: from_pool)

      expect(build(:pool_movement, from_pool: from_pool, to_pool: to_pool)).to be_valid
    end
  end

  # This table is the ledger of money movement, and `update_all` / `insert_all` / raw SQL
  # all walk straight past a model validation. A self-transfer is meaningless in every
  # case, so the database refuses it too.
  # rubocop:disable Rails/SkipsModelValidations -- skipping the validation is the point
  describe "database constraints" do
    it "refuses a self-transfer written past the validation" do
      movement = create(:pool_movement, from_pool: checking, to_pool: groceries)

      expect { movement.update_column(:to_pool_id, movement.from_pool_id) }
        .to raise_error(ActiveRecord::StatementInvalid, /pool_movements_distinct_pools/)
    end

    it "refuses a self-transfer inserted in bulk" do
      expect do
        described_class.insert_all!([{ from_pool_id: checking.id, to_pool_id: checking.id, amount: 10, date: Time.zone.now }])
      end.to raise_error(ActiveRecord::StatementInvalid, /pool_movements_distinct_pools/)
    end

    it "still admits a legitimate movement written past the validation" do
      movement = create(:pool_movement, from_pool: checking, to_pool: groceries)

      expect { movement.update_column(:to_pool_id, car.id) }.not_to raise_error
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  describe "#crosses_accounts?" do
    let(:savings_account) { create(:pool, :account, user: user, name: "Savings Account") }
    let(:vacation) { create(:pool, :savings_pool, user: user, account: savings_account) }

    it "is false for two pools in the same account" do
      movement = build(:pool_movement, from_pool: groceries, to_pool: car)

      expect(movement).not_to be_crosses_accounts
    end

    it "is false for a savings pool and a budget pool sharing an account" do
      rainy_day = create(:pool, :savings_pool, user: user, account: checking)
      movement = build(:pool_movement, from_pool: rainy_day, to_pool: groceries)

      expect(movement).not_to be_crosses_accounts
    end

    it "is false when moving from an account to its own pool" do
      movement = build(:pool_movement, from_pool: checking, to_pool: groceries)

      expect(movement).not_to be_crosses_accounts
    end

    it "is false when sweeping a pool back into its own account" do
      movement = build(:pool_movement, from_pool: groceries, to_pool: checking)

      expect(movement).not_to be_crosses_accounts
    end

    it "is true when the destination lives in a different account" do
      movement = build(:pool_movement, from_pool: checking, to_pool: vacation)

      expect(movement).to be_crosses_accounts
    end

    it "is true when the source lives in a different account than the destination account" do
      movement = build(:pool_movement, from_pool: vacation, to_pool: checking)

      expect(movement).to be_crosses_accounts
    end

    it "is true for two pools sitting in different accounts" do
      movement = build(:pool_movement, from_pool: groceries, to_pool: vacation)

      expect(movement).to be_crosses_accounts
    end

    it "is true between two accounts" do
      movement = build(:pool_movement, from_pool: checking, to_pool: savings_account)

      expect(movement).to be_crosses_accounts
    end

    it "is true between two unsaved accounts" do
      from_pool = build(:pool, :account, user: user)
      to_pool = build(:pool, :account, user: user)

      expect(build(:pool_movement, from_pool: from_pool, to_pool: to_pool)).to be_crosses_accounts
    end

    it "is false from an unsaved account into its own unsaved pool" do
      from_pool = build(:pool, :account, user: user)
      to_pool = build(:pool, :budget_pool, user: user, account: from_pool)

      expect(build(:pool_movement, from_pool: from_pool, to_pool: to_pool)).not_to be_crosses_accounts
    end

    # Savings pools may still be account-less until Plan 3 backfills accounts; such a pool
    # stands in for its own account, so any movement touching one reads as a crossing.
    it "is true when an account-less savings pool is involved" do
      orphan = create(:pool, user: user, account: nil)
      movement = build(:pool_movement, from_pool: checking, to_pool: orphan)

      expect(movement).to be_crosses_accounts
    end
  end

  describe "grouping by source entry" do
    it "is destroyed with its source entry" do
      income = create(:entry, :income)
      create(:pool_movement, from_pool: checking, to_pool: groceries, source_entry: income)

      expect { income.destroy }.to change(described_class, :count).by(-1)
    end

    it "collects the movements funded by one entry" do
      income = create(:entry, :income)
      allocation = create(:pool_movement, from_pool: checking, to_pool: groceries, source_entry: income)
      create(:pool_movement, from_pool: checking, to_pool: car)

      expect(described_class.for_entry(income)).to contain_exactly(allocation)
    end
  end

  describe "pool associations" do
    it "reaches a pool's movements from both ends", :aggregate_failures do
      inbound = create(:pool_movement, from_pool: checking, to_pool: groceries)
      outbound = create(:pool_movement, from_pool: groceries, to_pool: car)

      expect(groceries.movements_in).to contain_exactly(inbound)
      expect(groceries.movements_out).to contain_exactly(outbound)
    end

    it "is destroyed with either of its pools" do
      create(:pool_movement, from_pool: checking, to_pool: groceries)

      expect { groceries.destroy }.to change(described_class, :count).by(-1)
    end

    # Two foreign keys into pools means a user cascade has two chances to be blocked.
    it "is cleared away when its owner is destroyed" do
      create(:pool_movement, from_pool: checking, to_pool: groceries)

      expect { user.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
