# frozen_string_literal: true

require "rails_helper"

# A POOL IS AN ACCOUNT (two-ledger spec §5, Task 8), and this file is what is left of the pool era's
# 59 examples after the layer went. Everything it used to assert was about a shape that no longer
# exists — pool TYPES and their nouns, `account_id` and the nesting rules, `start_date`,
# `target_amount`, `priority`, the fill order, `#total`, `#timeline`, the auto-created categories,
# and the destroy-time re-pointing (`spec/models/pool_destroy_spec.rb`, deleted whole). The rules
# that survive are the ones that were always about a bank account: a name, an owner, two directions
# of movement, and the balance.
RSpec.describe Pool, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to have_many(:movements_in).dependent(:destroy) }
    it { is_expected.to have_many(:movements_out).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
  end

  # ONE MEMBER, AND THE COLUMN SURVIVES THE TYPE IT DISCRIMINATED. 1 and 2 are retired and never
  # reused: a backup or a staging database that missed the drop still holds envelopes and goals
  # under those integers.
  describe "pool_type" do
    it { is_expected.to define_enum_for(:pool_type).with_values(account: 0).with_prefix }

    it "refuses a type it does not know" do
      expect { build(:pool, pool_type: :budget) }.to raise_error(ArgumentError)
    end
  end

  describe "name uniqueness" do
    it "rejects a second pool with the same name for the same user", :aggregate_failures do
      user = create(:user)
      create(:pool, user: user, name: "Emergency Fund")

      duplicate = build(:pool, user: user, name: "Emergency Fund")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include("has already been taken")
    end

    it "compares names case-insensitively" do
      user = create(:user)
      create(:pool, user: user, name: "Emergency Fund")

      expect(build(:pool, user: user, name: "emergency fund")).not_to be_valid
    end

    it "allows the same name under a different user" do
      create(:pool, user: create(:user), name: "Emergency Fund")

      expect(build(:pool, user: create(:user), name: "Emergency Fund")).to be_valid
    end
  end

  # WHAT THE ACCOUNT HOLDS, through `AccountLedger` — the pot absorbs every entry there is and every
  # other account is movement-fed. One door, so a caller cannot build a second answer.
  describe "#balance" do
    let(:user) { create(:user) }
    let!(:main) { create(:pool, :account, user: user, name: "Checking") }
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    it "is the pot's entries net of what has been moved out of it", :aggregate_failures do
      income = create(:category, :income, user: user, name: "Salary")
      create(:entry, item: create(:item, category: income), amount: 3_000, date: Date.current)
      create(:account_movement, from_pool: main, to_pool: ally, amount: 750, date: Time.zone.now)

      expect(main.reload.balance).to eq(2_250)
      expect(ally.reload.balance).to eq(750)
    end

    it "is zero for an account nothing has reached" do
      expect(ally.balance).to eq(0)
    end
  end

  # ** THE MAIN ACCOUNT IS NOT DELETABLE WHILE IT IS MAIN (final fix wave, C-1). ** The regression
  # this replaces was reachable from Home's own Delete button: main is on one side of EVERY
  # AccountMovement the app writes, so `dependent: :destroy` took the whole physical ledger with it
  # and `pot + Σ accounts` went to 0 while the purpose ledger stood — two-ledger §2 broken by a
  # button. Both directions in every block: main refuses, a non-main account still deletes.
  describe "deleting" do
    let(:user) { create(:user) }
    let!(:main) { create(:pool, :account, user: user, name: "Checking") }
    let(:ally) { create(:pool, :account, user: user, name: "Ally") }

    it "refuses to destroy the main account, and says why", :aggregate_failures do
      expect(main.destroy).to be(false)
      expect(main.errors[:base]).to include("This is your main account — everything flows through it")
      expect(described_class.exists?(main.id)).to be(true)
    end

    it "destroys an account that is not main", :aggregate_failures do
      expect(ally.destroy).to be_truthy
      expect(described_class.exists?(ally.id)).to be(false)
    end

    # THE INVARIANT IS WHAT THE REFUSAL IS FOR, so it is asserted rather than alluded to: the movement
    # is main → Ally, which is the only shape either writer produces, and a successful destroy of main
    # would delete it and leave the pot with nothing to read entries against.
    it "leaves every movement and every balance standing when main is refused", :aggregate_failures do
      income = create(:category, :income, user: user, name: "Salary")
      create(:entry, item: create(:item, category: income), amount: 3_000, date: Date.current)
      create(:account_movement, from_pool: main, to_pool: ally, amount: 750, date: Time.zone.now)

      main.destroy

      expect(AccountMovement.count).to eq(1)
      expect(user.reload.default_account).to eq(main)
      expect([main.reload.balance, ally.reload.balance]).to eq([2_250, 750])
    end

    # ** AN ANSWERED ACCOUNT TAKES ITS OPENING RECORD WITH IT (fix round round 2 — item 4). **
    # `entries.opening_account_id` is a foreign key with no `dependent` of its own, so this raised
    # `PG::ForeignKeyViolation` — a 500 out of Home's Delete button on every account a user had
    # finished setting up. Both halves of the record go: the entry by `has_one :opening_entry,
    # dependent: :destroy`, and the transfer beside it through `Entry has_many :account_movements`.
    #
    # ** AND THE INVARIANT HOLDS ACROSS THE DELETE, which is the half a `:nullify` would have broken.
    # ** Re-derived: Ally opens at $500 — an income entry of $500 and a transfer main → Ally of $500,
    # which cancel on main — so destroying it leaves the pot exactly where it was and takes $500 off
    # what the household has everywhere. That money was never main's to get back.
    it "takes its opening record with it, and leaves the ledger square", :aggregate_failures do
      income = create(:category, :income, user: user, name: "Salary")
      create(:entry, item: create(:item, category: income), amount: 3_000, date: Date.current)
      expect(AccountOpening.new(user, ally, balance: "500").save).to be(true)
      entry = Entry.find_by!(opening_account_id: ally.id)

      expect(ally.destroy).to be_truthy

      expect(Entry.exists?(entry.id)).to be(false)
      expect(AccountMovement.count).to eq(0)
      expect(AccountLedger.new(user).pot).to eq(3_000)
      expect(ClaimLedger.new(user).total_money).to eq(3_000)
    end

    # THE ONE ESCAPE. `User has_many :pools, dependent: :destroy` reaches main like any other pool, and
    # a refusal there would make the user undeletable — `destroyed_by_association` is what stands the
    # callback down. Asserted because the guard is invisible until it is missing.
    it "goes with the user, whose deletion is the one thing that may take it", :aggregate_failures do
      ally

      expect(user.destroy).to be_truthy
      expect(described_class.where(id: [main.id, ally.id])).not_to exist
    end

    # PAST THE MODEL IS PAST THE REFUSAL, and that is a statement rather than a gap: this is a Ruby
    # callback, not a constraint, so `delete` writes the DELETE straight out. Recorded so the next
    # reader does not mistake the callback for a database-level guarantee — the pointer's own
    # `on_delete: :nullify` is what the schema says, and it says nothing about refusing.
    it "is a model refusal only, which `delete` walks straight past" do
      main.delete

      expect(described_class.exists?(main.id)).to be(false)
    end
  end

  describe "#main?" do
    let(:user) { create(:user) }
    let!(:main) { create(:pool, :account, user: user, name: "Checking") }

    it "is true for the account the user's pointer names, and false for the next one", :aggregate_failures do
      ally = create(:pool, :account, user: user, name: "Ally")

      expect(main).to be_main
      expect(ally).not_to be_main
    end

    it "is false for every account once the user names none" do
      user.update!(default_account: nil)

      expect(main.reload).not_to be_main
    end
  end

  describe ".accounts" do
    it "returns the user's accounts" do
      user = create(:user)
      checking = create(:pool, :account, user: user, name: "Checking")

      expect(user.pools.accounts).to contain_exactly(checking)
    end
  end

  # ===============================================================================================
  # THE DATABASE'S OWN HALF (two-ledger spec §5). Every example here writes PAST the model —
  # `save!(validate: false)`, `update_column`, raw SQL — and that is the entire point: what these
  # prove is that the refusal survives a writer that never asked the model. A console session, an
  # `update_all`, an import, a future controller.
  # ===============================================================================================
  describe "the constraints in the schema" do
    let(:user) { create(:user) }
    let(:checking) { create(:pool, :account, user: user, name: "Checking") }

    describe "pools_are_accounts" do
      it "refuses a pool typed as anything else, past the model" do
        expect { ActiveRecord::Base.connection.execute(<<~SQL.squish) }
          INSERT INTO pools (id, user_id, name, pool_type, created_at, updated_at)
          VALUES ('#{SecureRandom.uuid}', '#{user.id}', 'Smuggled', 1, NOW(), NOW())
        SQL
          .to raise_error(ActiveRecord::StatementInvalid, /pools_are_accounts/)
      end

      it "accepts the one shape it exists to allow" do
        expect { checking }.not_to raise_error
      end
    end

    describe "index_pools_on_user_id_and_lower_name" do
      it "refuses a duplicate name past the model" do
        create(:pool, :account, user: user, name: "Emergency Fund")
        twin = build(:pool, :account, user: user, name: "Emergency Fund")

        expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      # THE FUNCTIONAL HALF, and the reason the index is on `lower(name)` rather than on the
      # column: the model's uniqueness is case-insensitive, so an index on the raw name would
      # accept a pair the model refuses and guard nothing the model does not already guard.
      it "refuses a name differing only in case past the model" do
        create(:pool, :account, user: user, name: "Emergency Fund")
        twin = build(:pool, :account, user: user, name: "emergency fund")

        expect { twin.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
      end

      it "accepts the same name under a different user, which is what the scope is for" do
        create(:pool, :account, user: user, name: "Emergency Fund")

        expect { create(:pool, :account, user: create(:user), name: "Emergency Fund") }.not_to raise_error
      end
    end

    # THE COLUMN DEFAULT MOVED WITH THE CHECK (Task 8). `TightenPoolShape` set it to `budget`
    # because an envelope was the ordinary pool this app made; a `Pool.new` that named no type would
    # now come back from the database already refused by `pools_are_accounts`. Asserted on a bare
    # `Pool.new` rather than through the factory, which sets the type explicitly — the default is
    # only ever met by a writer that names none.
    describe "the column defaults" do
      it "opens a typeless pool as an account" do
        expect(described_class.new.pool_type).to eq("account")
      end
    end
  end
end
