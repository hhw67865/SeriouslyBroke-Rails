# frozen_string_literal: true

require "rails_helper"

# A TRANSFER BETWEEN TWO OF ONE USER'S OWN ACCOUNTS (two-ledger spec §5, Task 8). What this file
# stopped asserting, and why: `#crosses_accounts?` and its eleven examples are gone with the
# question — both ends of every row are accounts, so nothing sits INSIDE anything for a movement to
# cross out of — and `.distributed` is gone with the `allocation` and `sweep` kinds, which a
# distribution now writes on `allocations` and finds again through `Allocation.distributed`.
RSpec.describe AccountMovement, type: :model do
  let(:user) { create(:user) }
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:groceries) { create(:pool, :account, user: user, name: "Groceries Account") }
  let(:car) { create(:pool, :account, user: user, name: "Car Account") }

  describe "associations" do
    it { is_expected.to belong_to(:from_pool).class_name("Pool") }
    it { is_expected.to belong_to(:to_pool).class_name("Pool") }
    it { is_expected.to belong_to(:source_entry).class_name("Entry").optional }
  end

  describe "factory" do
    it "builds a valid movement" do
      expect(build(:account_movement)).to be_valid
    end

    it "creates a movement between two accounts of one user", :aggregate_failures do
      movement = create(:account_movement)

      expect(movement).to be_persisted
      expect(movement.to_pool.user).to eq(movement.from_pool.user)
    end
  end

  describe "validations" do
    it "accepts a positive amount between two accounts of the same user" do
      expect(build(:account_movement, from_pool: checking, to_pool: groceries, amount: 25.00)).to be_valid
    end

    it "requires a positive amount", :aggregate_failures do
      movement = build(:account_movement, from_pool: checking, to_pool: groceries, amount: 0)

      expect(movement).not_to be_valid
      expect(movement.errors[:amount]).to include("must be greater than 0")
    end

    it "requires a date", :aggregate_failures do
      movement = build(:account_movement, from_pool: checking, to_pool: groceries, date: nil)

      expect(movement).not_to be_valid
      expect(movement.errors[:date]).to include("can't be blank")
    end

    it "rejects a movement to the same account", :aggregate_failures do
      movement = build(:account_movement, from_pool: checking, to_pool: checking)

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must differ from the source account")
    end

    it "allows a movement between two distinct accounts", :aggregate_failures do
      movement = build(:account_movement, from_pool: groceries, to_pool: car)

      expect(movement).to be_valid
      expect(movement.errors[:to_pool]).to be_empty
    end

    it "rejects a movement between two users' accounts", :aggregate_failures do
      movement = build(:account_movement, from_pool: checking, to_pool: create(:pool, :account))

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must belong to the same user")
    end

    # Unsaved accounts carry a nil id and a nil user_id, so an id comparison reads
    # `nil == nil` and waves the record through. The records themselves must decide.
    it "rejects a movement to the same unsaved account", :aggregate_failures do
      pool = build(:pool, :account)
      movement = build(:account_movement, from_pool: pool, to_pool: pool)

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must differ from the source account")
    end

    it "rejects a movement between two unsaved accounts of different users", :aggregate_failures do
      movement = build(
        :account_movement,
        from_pool: build(:pool, :account, user: build(:user)),
        to_pool: build(:pool, :account, user: build(:user))
      )

      expect(movement).not_to be_valid
      expect(movement.errors[:to_pool]).to include("must belong to the same user")
    end

    # Comparing the users is only half the guard: two accounts that name no user at all read
    # `nil == nil` and pass, so a movement between two ownerless accounts was accepted.
    it "rejects a movement between two accounts that name no user", :aggregate_failures do
      movement = described_class.new(
        from_pool: Pool.new(pool_type: :account),
        to_pool: Pool.new(pool_type: :account),
        amount: 25.00,
        date: Date.current
      )

      movement.valid?

      expect(movement.errors[:to_pool]).to include("must belong to the same user")
    end

    it "allows a movement between two unsaved accounts of one user" do
      unsaved_user = build(:user)
      from_pool = build(:pool, :account, user: unsaved_user)
      to_pool = build(:pool, :account, user: unsaved_user, name: "Ally")

      expect(build(:account_movement, from_pool: from_pool, to_pool: to_pool)).to be_valid
    end

    # SPEC §7a. The column is a bare foreign key to `entries` with no user on it, so nothing
    # but this stops a movement between MY accounts from naming a STRANGER'S paycheck as its
    # cause. The money would still land correctly — the physical partition equals bank truth
    # either way — while `Entry#routed_account` answered about a stranger's deposit.
    describe "source_entry ownership" do
      let(:own_income) do
        create(:entry, item: create(:item, category: create(:category, :income, user: user)))
      end

      it "accepts an entry belonging to the accounts' owner", :aggregate_failures do
        movement = build(:account_movement, from_pool: checking, to_pool: groceries, source_entry: own_income)

        expect(movement).to be_valid
        expect(movement.errors[:source_entry]).to be_empty
      end

      it "accepts no source entry at all — the column is optional" do
        expect(build(:account_movement, from_pool: checking, to_pool: groceries, source_entry: nil)).to be_valid
      end

      it "rejects an entry belonging to another user", :aggregate_failures do
        movement = build(:account_movement, from_pool: checking, to_pool: groceries, source_entry: create(:entry, :income))

        expect(movement).not_to be_valid
        expect(movement.errors[:source_entry]).to include("must belong to the same user")
      end

      # Under `build` nothing is persisted and every id is nil, so an id comparison reads
      # `nil == nil` and waves the foreign entry through.
      it "rejects an unsaved entry belonging to another unsaved user", :aggregate_failures do
        unsaved_user = build(:user)
        from_pool = build(:pool, :account, user: unsaved_user)
        to_pool = build(:pool, :account, user: unsaved_user, name: "Ally")
        foreign = build(:entry, item: build(:item, category: build(:category, :income, user: build(:user))))
        movement = build(:account_movement, from_pool: from_pool, to_pool: to_pool, source_entry: foreign)

        expect(movement).not_to be_valid
        expect(movement.errors[:source_entry]).to include("must belong to the same user")
      end

      it "accepts an unsaved entry belonging to the same unsaved user" do
        unsaved_user = build(:user)
        from_pool = build(:pool, :account, user: unsaved_user)
        to_pool = build(:pool, :account, user: unsaved_user, name: "Ally")
        own = build(:entry, item: build(:item, category: build(:category, :income, user: unsaved_user)))

        expect(build(:account_movement, from_pool: from_pool, to_pool: to_pool, source_entry: own)).to be_valid
      end

      # The both-nil hole #accounts_must_share_a_user closes, on the third edge: an entry
      # naming no user must not match accounts naming none either.
      it "rejects an entry that names no user when the accounts name none", :aggregate_failures do
        movement = described_class.new(
          from_pool: Pool.new(pool_type: :account),
          to_pool: Pool.new(pool_type: :account),
          source_entry: Entry.new(amount: 10, date: Date.current),
          amount: 25.00,
          date: Date.current
        )

        movement.valid?

        expect(movement.errors[:source_entry]).to include("must belong to the same user")
      end

      # A validation must return an ANSWER for every record it is handed. `Entry#user`
      # delegates through `item` without `allow_nil`, so reaching for it raises on a
      # half-built entry — and a NoMethodError out of `valid?` is not a rejection.
      it "answers rather than raising when the entry has no item" do
        movement = build(
          :account_movement,
          from_pool: checking,
          to_pool: groceries,
          source_entry: Entry.new(amount: 10, date: Date.current)
        )

        expect { movement.valid? }.not_to raise_error
      end
    end
  end

  # This table is the ledger of money movement, and `update_all` / `insert_all` / raw SQL
  # all walk straight past a model validation.
  # rubocop:disable Rails/SkipsModelValidations -- skipping the validation is the point
  describe "database constraints" do
    it "refuses a self-transfer written past the validation" do
      movement = create(:account_movement, from_pool: checking, to_pool: groceries)

      expect { movement.update_column(:to_pool_id, movement.from_pool_id) }
        .to raise_error(ActiveRecord::StatementInvalid, /account_movements_distinct_accounts/)
    end

    it "refuses a self-transfer inserted in bulk" do
      expect do
        described_class.insert_all!([{ from_pool_id: checking.id, to_pool_id: checking.id, amount: 10, date: Time.zone.now }])
      end.to raise_error(ActiveRecord::StatementInvalid, /account_movements_distinct_accounts/)
    end

    it "still admits a legitimate movement written past the validation" do
      movement = create(:account_movement, from_pool: checking, to_pool: groceries)

      expect { movement.update_column(:to_pool_id, car.id) }.not_to raise_error
    end

    # A self-transfer is meaningless but nets to zero; a negative amount silently inverts
    # the direction of the transfer, so money leaves the account the row says it enters.
    it "refuses a negative amount written past the validation" do
      movement = create(:account_movement, from_pool: checking, to_pool: groceries)

      expect { movement.update_column(:amount, -10) }
        .to raise_error(ActiveRecord::StatementInvalid, /account_movements_positive_amount/)
    end

    it "refuses a zero amount inserted in bulk" do
      expect do
        described_class.insert_all!([{ from_pool_id: checking.id, to_pool_id: groceries.id, amount: 0, date: Time.zone.now }])
      end.to raise_error(ActiveRecord::StatementInvalid, /account_movements_positive_amount/)
    end

    it "still admits a positive amount written past the validation" do
      movement = create(:account_movement, from_pool: checking, to_pool: groceries)

      expect { movement.update_column(:amount, 0.01) }.not_to raise_error
    end

    # THE KIND SHRANK TO ONE MEMBER AND THE DATABASE HOLDS IT (Task 8). The enum refuses `1` in
    # Ruby; this is the half that survives an `update_all`, an import or a console.
    it "refuses a kind that is not a transfer, past the model" do
      movement = create(:account_movement, from_pool: checking, to_pool: groceries)

      expect { movement.update_column(:kind, 1) }
        .to raise_error(ActiveRecord::StatementInvalid, /account_movements_are_transfers/)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  describe "grouping by source entry" do
    let(:income) { create(:entry, item: create(:item, category: create(:category, :income, user: user))) }

    it "is destroyed with its source entry" do
      create(:account_movement, from_pool: checking, to_pool: groceries, source_entry: income)

      expect { income.destroy }.to change(described_class, :count).by(-1)
    end

    it "collects the movements caused by one entry" do
      routing = create(:account_movement, from_pool: checking, to_pool: groceries, source_entry: income)
      create(:account_movement, from_pool: checking, to_pool: car)

      expect(described_class.for_entry(income)).to contain_exactly(routing)
    end
  end

  describe "kind" do
    it { is_expected.to define_enum_for(:kind).with_values(transfer: 0).with_prefix }

    it "defaults to a transfer", :aggregate_failures do
      movement = create(:account_movement, from_pool: checking, to_pool: groceries)

      expect(movement.kind).to eq("transfer")
      expect(movement).to be_kind_transfer
    end

    it "refuses a kind the enum no longer knows" do
      expect { build(:account_movement, kind: :allocation) }.to raise_error(ArgumentError)
    end
  end

  describe "account associations" do
    it "reaches an account's movements from both ends", :aggregate_failures do
      inbound = create(:account_movement, from_pool: checking, to_pool: groceries)
      outbound = create(:account_movement, from_pool: groceries, to_pool: car)

      expect(groceries.movements_in).to contain_exactly(inbound)
      expect(groceries.movements_out).to contain_exactly(outbound)
    end

    it "is destroyed with either of its accounts" do
      create(:account_movement, from_pool: checking, to_pool: groceries)

      expect { groceries.destroy }.to change(described_class, :count).by(-1)
    end

    # Two foreign keys into pools means a user cascade has two chances to be blocked.
    it "is cleared away when its owner is destroyed" do
      create(:account_movement, from_pool: checking, to_pool: groceries)

      expect { user.destroy }.to change(described_class, :count).by(-1)
    end
  end
end
