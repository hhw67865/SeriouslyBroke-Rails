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
