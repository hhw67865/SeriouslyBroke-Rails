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
