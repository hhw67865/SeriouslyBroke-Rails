# frozen_string_literal: true

require "rails_helper"

# THE PURPOSE LEDGER'S OWN ROW. A side is a category or NULL, and NULL means AVAILABLE — so the
# four legal shapes are available → category, category → available, category → category, and
# nothing at all, which is the one this refuses.
RSpec.describe Allocation, type: :model do
  let(:user) { create(:user) }
  let(:food) { create(:category, :expense, :funded, user: user, name: "Food") }
  let(:rent) { create(:category, :expense, :funded, user: user, name: "Rent") }

  def allocation(**attrs) = described_class.new({ amount: 100, date: Time.zone.now }.merge(attrs))

  describe "the shapes it accepts" do
    it "accepts available → a category" do
      expect(allocation(to_category: food)).to be_valid
    end

    it "accepts a category → available" do
      expect(allocation(from_category: food)).to be_valid
    end

    it "accepts a category → another category, which is the hand move" do
      expect(allocation(from_category: food, to_category: rent)).to be_valid
    end
  end

  describe "the shapes it refuses" do
    # Available → available is not a move at all: it is the whole purpose ledger claiming to have
    # rearranged itself. The `allocations_distinct_sides` CHECK refuses it a second time, past the
    # model — `NULL IS DISTINCT FROM NULL` is false in Postgres.
    it "refuses an allocation with no category on either side", :aggregate_failures do
      record = allocation

      expect(record).not_to be_valid
      expect(record.errors[:base]).to include("needs at least one category")
    end

    it "refuses a category allocating to itself", :aggregate_failures do
      record = allocation(from_category: food, to_category: food)

      expect(record).not_to be_valid
      expect(record.errors[:to_category]).to include("must differ from the source")
    end

    it "refuses two users' categories in one allocation", :aggregate_failures do
      theirs = create(:category, :expense, :funded, user: create(:user), name: "Their Food")
      record = allocation(from_category: food, to_category: theirs)

      expect(record).not_to be_valid
      expect(record.errors[:base]).to include("must stay within one user")
    end

    # ONLY EXPENSE CATEGORIES HOLD MONEY (spec §3). Income lands in available and is allocated OUT
    # of it; an allocation naming an income category would be money given a purpose it can never be
    # spent against — `CategoryLedger` reads a category's spending out of `Entry.expenses`, so an
    # income category's own entries could never drain the holding this row would create.
    it "refuses an income category on either side", :aggregate_failures do
      pay = create(:category, :income, user: user, name: "Pay")

      expect(allocation(to_category: pay)).not_to be_valid
      expect(allocation(from_category: pay).tap(&:valid?).errors[:base])
        .to include("only expense categories hold money")
    end

    it "refuses a zero or negative amount", :aggregate_failures do
      expect(allocation(to_category: food, amount: 0)).not_to be_valid
      expect(allocation(to_category: food, amount: -5)).not_to be_valid
    end

    it "refuses a dateless allocation" do
      expect(allocation(to_category: food, date: nil)).not_to be_valid
    end
  end

  describe "#user" do
    it "reads the owner off whichever side it has", :aggregate_failures do
      expect(allocation(to_category: food).user).to eq(user)
      expect(allocation(from_category: food).user).to eq(user)
    end
  end

  # THE GUARD `AccountMovement` HAS CARRIED SINCE PLAN 2 (spec §7a), ported here by Task 4 — the task
  # that writes the first `source_entry` allocations. `allocations.source_entry_id` is a bare FK to
  # `entries` and no column on this table says whose entry it is, so without this an allocation
  # between MY categories may name a STRANGER'S paycheck as its cause. The money would still land
  # correctly — both partitions of the invariant hold either way — while "replace this period's
  # distribution" keyed off an entry belonging to somebody else.
  describe "source_entry ownership" do
    let(:own_income) do
      create(:entry, item: create(:item, category: create(:category, :income, user: user)))
    end

    it "accepts an entry belonging to the categories' owner", :aggregate_failures do
      record = allocation(to_category: food, source_entry: own_income)

      expect(record).to be_valid
      expect(record.errors[:source_entry]).to be_empty
    end

    it "accepts no source entry at all — the column is optional" do
      expect(allocation(to_category: food, source_entry: nil)).to be_valid
    end

    it "rejects an entry belonging to another user", :aggregate_failures do
      record = allocation(to_category: food, source_entry: create(:entry, :income))

      expect(record).not_to be_valid
      expect(record.errors[:source_entry]).to include("must belong to the same user")
    end

    # THE SWEEP DIRECTION, where the owner is read off `from_category` instead — `#user` answers
    # from whichever side exists, and a guard that only ever looked at `to_category` would wave
    # every sweep's source entry through.
    it "rejects a stranger's entry on a sweep, which names only a source", :aggregate_failures do
      record = allocation(from_category: food, source_entry: create(:entry, :income))

      expect(record).not_to be_valid
      expect(record.errors[:source_entry]).to include("must belong to the same user")
    end

    # Under `build` nothing is persisted and every id is nil, so an id comparison reads
    # `nil == nil` and waves the foreign entry through. Records, not ids.
    it "rejects an unsaved entry belonging to another unsaved user", :aggregate_failures do
      unsaved_user = build(:user)
      mine = build(:category, :expense, :funded, user: unsaved_user)
      foreign = build(:entry, item: build(:item, category: build(:category, :income, user: build(:user))))
      record = allocation(to_category: mine, source_entry: foreign)

      expect(record).not_to be_valid
      expect(record.errors[:source_entry]).to include("must belong to the same user")
    end

    # A validation must return an ANSWER for every record it is handed, including the invalid ones:
    # `Entry#user` delegates through `item` without `allow_nil`, so a half-built entry raises and a
    # NoMethodError out of `valid?` is not a rejection.
    it "refuses rather than raising on an entry with no item", :aggregate_failures do
      record = allocation(to_category: food, source_entry: Entry.new(amount: 10, date: Time.zone.now))

      expect { record.valid? }.not_to raise_error
      expect(record.errors[:source_entry]).to include("must belong to the same user")
    end
  end

  # THE FLOOR AT THE WRITE, on the `:reallocation` context only — see the validator for why a
  # distribution's own rows must not pay for a live balance query they have already answered.
  describe "#source_must_hold_it" do
    before { create(:allocation, to_category: food, amount: 100, date: Time.zone.now) }

    it "refuses a hand move larger than the source holds", :aggregate_failures do
      record = allocation(from_category: food, to_category: rent, amount: 300)

      expect(record.valid?(:reallocation)).to be(false)
      expect(record.errors[:amount]).to include("is more than Food holds — it has $100.00")
    end

    # The paired positive, at the exact boundary: a move of everything the source holds is allowed,
    # so the refusal above is a comparison rather than a blanket no.
    it "accepts a hand move of exactly what the source holds" do
      expect(allocation(from_category: food, to_category: rent, amount: 100).valid?(:reallocation)).to be(true)
    end

    # AVAILABLE IS A SOURCE TOO, and its balance is the ROOT's rather than any category's. Nothing
    # has been paid in here, so $100 was allocated OUT of an available of zero and the root reads
    # -$100 — which cannot fund anything, and the message names it by the name the screen prints.
    it "refuses a hand move out of an available that cannot cover it", :aggregate_failures do
      record = allocation(to_category: rent, amount: 50)

      expect(record.valid?(:reallocation)).to be(false)
      expect(record.errors[:amount]).to include("is more than Available holds — it has -$100.00")
    end

    # OFF THE CONTEXT IT IS SILENT, which is the half that keeps a distribution's own rows cheap: the
    # same record that is refused above saves without complaint on the default context.
    it "says nothing on the default context" do
      expect(allocation(from_category: food, to_category: rent, amount: 300)).to be_valid
    end
  end

  describe "the scopes a distribution replaces itself by" do
    let!(:hand_move) { create(:allocation, to_category: food, kind: :transfer) }
    let!(:distributed) { create(:allocation, to_category: food, kind: :allocation) }
    let!(:swept) { create(:allocation, from_category: food, kind: :sweep) }

    # The vocabulary `AllocationCommitter` needs to REPLACE a period's split without taking the
    # user's own hand moves with it — `transfer` is the default and is deliberately outside it.
    it "counts allocations and sweeps as distributed, and a transfer as not" do
      expect(described_class.distributed).to contain_exactly(distributed, swept)
    end

    it "finds the rows one entry caused" do
      entry = create(:entry, item: create(:item, category: create(:category, :income, user: user)))
      caused = create(:allocation, to_category: food, source_entry: entry)

      expect(described_class.for_entry(entry)).to contain_exactly(caused)
    end

    it "leaves the hand move out of both" do
      expect(described_class.distributed).not_to include(hand_move)
    end
  end
end
