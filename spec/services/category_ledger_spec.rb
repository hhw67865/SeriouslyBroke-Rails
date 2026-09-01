# frozen_string_literal: true

require "rails_helper"

# THE PURPOSE LEDGER'S READER — what each category holds, and what is still available.
#
# EVERY FIGURE BELOW IS A PLANTED LITERAL, for `PoolBalanceLedger`'s reason: an assertion of the
# form `ledger.available == <something derived from the ledger>` is `x == x` and would pass against
# a class summing the wrong column. Each term is asserted against the amount the fixture put there.
RSpec.describe CategoryLedger, type: :model do
  let(:user) { create(:user) }
  let(:food) { create(:category, :expense, user: user, name: "Food", funded_since: Date.new(2026, 8, 1)) }
  let(:misc) { create(:category, :expense, user: user, name: "Misc") }
  let(:pay) { create(:category, :income, user: user, name: "Pay") }
  let(:ledger) { described_class.new([food, misc]) }

  # The user's MAIN account, referenced by nothing on purpose: `categories.pool_id` still exists and
  # the category factory reaches for `user.default_account` when a spec does not name a pool.
  before { create(:pool, :account, user: user, name: "Checking") }

  def spend(category, amount, on:)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  def earn(amount, on:)
    create(:entry, item: create(:item, category: pay), amount: amount, date: on)
  end

  describe "#terms_for" do
    # Food: $300 allocated in (Aug 2), $50 back out (Aug 3), $40 spent while funded (Aug 5) and
    # $10 spent before it was funded (Jul 20) — which drains available, not Food.
    before do
      create(:allocation, to_category: food, amount: 300, date: Time.zone.parse("2026-08-02 12:00"))
      create(:allocation, from_category: food, amount: 50, date: Time.zone.parse("2026-08-03 12:00"))
      spend(food, 40, on: Date.new(2026, 8, 5))
      spend(food, 10, on: Date.new(2026, 7, 20))
    end

    it "reports the five terms a calculator consumes", :aggregate_failures do
      terms = ledger.terms_for(food)

      expect(terms[:expense]).to eq(40)
      expect(terms[:movements_in]).to eq(300)
      expect(terms[:movements_out]).to eq(50)
      expect(terms[:last_funded_on]).to eq(Time.zone.parse("2026-08-02 12:00"))
    end

    # INCOME NEVER LANDS IN A CATEGORY — it lands in available (§2). The key is present and zero
    # rather than absent, so the hash stays the shape `PoolBalanceLedger#terms_for` hands out and a
    # calculator reading it gets an answer rather than a KeyError.
    #
    # A FUNDED INCOME CATEGORY, PLANTED PAST THE MODEL (`#holding_columns_are_sane` refuses the
    # shape) AND HOLDING A REAL $1,000 INCOME ENTRY — because the claim is about a category an
    # income entry NAMES, and a fixture without one asserts a zero that no arrangement of rows could
    # have made non-zero. Both terms: the income key is zero, and the entry drains nothing either.
    it "answers zero income for a category, even one an income entry names", :aggregate_failures do
      pay.update_columns(funded_since: Date.new(2026, 8, 1)) # rubocop:disable Rails/SkipsModelValidations
      earn(1000, on: Date.new(2026, 8, 5))
      over_income = described_class.new([pay, food])

      expect(over_income.terms_for(pay)[:income]).to eq(0)
      expect(over_income.terms_for(pay)[:expense]).to eq(0)
      expect(ledger.terms_for(food)[:income]).to eq(0)
    end

    it "answers a decimal zero for every term of a category with nothing", :aggregate_failures do
      terms = ledger.terms_for(misc)

      money = terms.values_at(:income, :expense, :movements_in, :movements_out)
      expect(money).to all(eq(0))
      # DECIMAL zeros, not Integer ones: an Integer leaks out through every calculator that
      # subtracts from it, on exactly the categories that hold nothing.
      expect(money).to all(be_a(BigDecimal))
      expect(terms[:last_funded_on]).to be_nil
    end

    # A category outside the set was never asked about, which is a different fact from holding
    # nothing — `PoolBalanceLedger#terms_for`'s own rule, and the reason #holding_of raises rather
    # than answering zero.
    it "answers nil for a category this ledger was not built over" do
      expect(ledger.terms_for(create(:category, :expense, :funded, user: user, name: "Fresh"))).to be_nil
    end
  end

  describe "#holding_of" do
    it "is allocations in, minus allocations out, minus the spending it counts" do
      create(:allocation, to_category: food, amount: 300, date: Time.zone.parse("2026-08-02 12:00"))
      create(:allocation, from_category: food, amount: 50, date: Time.zone.parse("2026-08-03 12:00"))
      spend(food, 40, on: Date.new(2026, 8, 5))

      expect(ledger.holding_of(food)).to eq(210)
    end

    it "refuses a category this ledger was not built over" do
      fresh = create(:category, :expense, :funded, user: user, name: "Fresh")

      expect { ledger.holding_of(fresh) }.to raise_error(described_class::UnknownCategory, /Fresh/)
    end

    # A HAND MOVE BETWEEN TWO CATEGORIES TOUCHES NEITHER ROOT: $80 leaves Food and arrives in Rent,
    # and available is the same figure on both sides of it.
    it "moves money between two categories without touching available", :aggregate_failures do
      rent = create(:category, :expense, :funded, user: user, name: "Rent")
      earn(500, on: Date.new(2026, 8, 1))
      create(:allocation, to_category: food, amount: 200, date: Time.zone.parse("2026-08-02 12:00"))
      create(:allocation, from_category: food, to_category: rent, amount: 80, date: Time.zone.parse("2026-08-04 12:00"))

      both = described_class.new([food, rent])
      expect([both.holding_of(food), both.holding_of(rent)]).to eq([120, 80])
      expect(both.available).to eq(300)
    end
  end

  describe "#available" do
    it "is income, less unfunded spending, less what is allocated out, plus what comes back" do
      earn(1000, on: Date.new(2026, 8, 5))
      spend(misc, 25, on: Date.new(2026, 8, 7)) # a category that was never funded
      spend(food, 10, on: Date.new(2026, 7, 20)) # before Food was funded
      create(:allocation, to_category: food, amount: 300, date: Time.zone.parse("2026-08-06 12:00"))
      create(:allocation, from_category: food, amount: 50, date: Time.zone.parse("2026-08-09 12:00"))

      expect(ledger.available).to eq(715)
    end

    it "counts a funded category's own spending against the category rather than against available", :aggregate_failures do
      earn(100, on: Date.new(2026, 8, 1))
      create(:allocation, to_category: food, amount: 60, date: Time.zone.parse("2026-08-02 12:00"))
      spend(food, 15, on: Date.new(2026, 8, 5))

      expect(ledger.available).to eq(40)
      expect(ledger.holding_of(food)).to eq(45)
    end

    it "ignores another user's income and spending entirely" do
      earn(100, on: Date.new(2026, 8, 1))
      stranger = create(:user)
      create(:pool, :account, user: stranger, name: "Their Checking")
      create(:entry, item: create(:item, category: create(:category, :income, user: stranger)), amount: 999)

      expect(ledger.available).to eq(100)
    end

    # AVAILABLE IS A FACT ABOUT A USER, not about the category set a screen happens to be asking
    # about — so a ledger that cannot name one user refuses rather than answering zero.
    it "refuses to answer for an empty set with no user named" do
      expect { described_class.new([]).available }.to raise_error(described_class::NoSingleOwner)
    end

    it "answers for an empty set when the user is named" do
      earn(100, on: Date.new(2026, 8, 1))

      expect(described_class.new([], user: user).available).to eq(100)
    end

    it "refuses a set spanning two users" do
      theirs = create(:category, :expense, :funded, user: create(:user), name: "Their Food")

      expect { described_class.new([food, theirs]).available }.to raise_error(described_class::NoSingleOwner)
    end
  end

  # THE RE-ANCHORED START-DATE RULE (spec §4), in SQL. Its Ruby mirror is pinned over the same two
  # instants in spec/models/category_holdings_spec.rb.
  describe "the funding boundary" do
    it "drains available before the funding day and the category on it", :aggregate_failures do
      spend(food, 12, on: Date.new(2026, 7, 31))
      spend(food, 7, on: Date.new(2026, 8, 1))

      expect(ledger.holding_of(food)).to eq(-7)
      expect(ledger.available).to eq(-12)
    end

    it "reads the boundary in the user's own timezone rather than UTC", :aggregate_failures do
      user.update!(timezone: "Asia/Tokyo")
      spend(food, 30, on: Time.utc(2026, 7, 31, 15, 0))
      spend(food, 7, on: Time.utc(2026, 7, 31, 14, 0))

      expect(ledger.holding_of(food)).to eq(-30)
      expect(ledger.available).to eq(-7)
    end

    it "sends every entry of a never-funded category to available", :aggregate_failures do
      spend(misc, 25, on: Date.new(2020, 1, 1))
      spend(misc, 5, on: Date.current)

      expect(ledger.holding_of(misc)).to eq(0)
      expect(ledger.available).to eq(-30)
    end
  end

  describe "#as_of" do
    before do
      create(:allocation, to_category: food, amount: 300, date: Time.zone.parse("2026-07-15 12:00"))
      create(:allocation, to_category: food, amount: 100, date: Time.zone.parse("2026-08-15 12:00"))
      earn(500, on: Date.new(2026, 7, 10))
      earn(90, on: Date.new(2026, 8, 20))
      spend(food, 40, on: Date.new(2026, 8, 20))
    end

    it "bounds every term at the moment it was built for", :aggregate_failures do
      bounded = described_class.new([food, misc], as_of: Date.new(2026, 8, 1))

      expect(bounded.holding_of(food)).to eq(300)
      expect(bounded.available).to eq(200)
    end

    it "sees the whole world when it is unbounded", :aggregate_failures do
      expect(ledger.holding_of(food)).to eq(360)
      expect(ledger.available).to eq(190)
    end

    # ONE LEDGER PER `as_of`, NEVER ONE SHARED ACROSS TWO — `PoolBalanceLedger`'s rule, and it is
    # here for the same reason: a ledger bounded at July answers a screen asking about today with
    # real, well-formed, month-old figures that no reader downstream can tell are wrong.
    it "hands itself over only to a caller asking about the same moment", :aggregate_failures do
      bounded = described_class.new([food], as_of: Date.new(2026, 8, 1))

      expect(bounded.for_as_of!(Date.new(2026, 8, 1))).to be(bounded)
      expect { bounded.for_as_of!(nil) }.to raise_error(described_class::AsOfMismatch)
    end
  end

  # A SNAPSHOT, STALE AFTER A WRITE — but read at FIRST USE rather than at construction, so a
  # ledger built before a write and read after it reports the write.
  it "reads the ledger at first use rather than at construction" do
    built_first = described_class.new([food])
    create(:allocation, to_category: food, amount: 75, date: Time.zone.now)

    expect(built_first.holding_of(food)).to eq(75)
  end
end
