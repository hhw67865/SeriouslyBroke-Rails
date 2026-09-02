# frozen_string_literal: true

require "rails_helper"

# ONBOARDING STEP 3 (main-account spec §5): after the other accounts are funded, main is
# wrong by exactly the untracked history. ONE ordinary entry in an auto-created
# "Opening Balance" category sets it to the real bank number — income-type when the
# correction raises main, expense-type when it lowers it. One-time by construction.
RSpec.describe "OpeningBalances", type: :request do
  let(:user) { create(:user) }
  let(:main) { create(:pool, :account, user: user, name: "Main") }

  before do
    user.update!(default_account: main)
    sign_in user, scope: :user
  end

  def app_balance = PoolCalculator.new(main.reload).balance

  # THE ONE ENTRY THE CORRECTION WRITES. `sole` twice deliberately: the correction is exactly one
  # category, one item and one entry, so a second of any of them is a failure here rather than a
  # `first` that quietly picks one.
  def correction_entry = user.categories.find_by(name: "Opening Balance").items.sole.entries.sole

  it "raises main to the entered figure with an income-type correction", :aggregate_failures do
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 300, date: Date.current)

    post opening_balance_path, params: { opening_balance: { actual: 1000 } }

    expect(app_balance).to eq(1000)
    correction = user.categories.find_by(name: "Opening Balance")
    expect(correction).to be_income
    expect(correction.pool).to eq(main)
    expect(correction_entry.date.to_date).to eq(Date.current - 1)
  end

  it "lowers main with an expense-type correction when the app holds too much", :aggregate_failures do
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 300, date: Date.current)

    post opening_balance_path, params: { opening_balance: { actual: 120 } }

    expect(app_balance).to eq(120)
    expect(user.categories.find_by(name: "Opening Balance")).to be_expense
  end

  it "refuses a second correction", :aggregate_failures do
    post opening_balance_path, params: { opening_balance: { actual: 100 } }
    post opening_balance_path, params: { opening_balance: { actual: 999 } }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("already")
    expect(app_balance).to eq(100)
  end

  # A ZERO DIFFERENCE (the branch left uncovered by the three examples above, both of which move
  # main): the app already agrees with the bank, so nothing is written — no category, no item, no
  # entry — and the user is told so rather than left to wonder whether the click did anything.
  it "writes nothing when the entered figure already matches main", :aggregate_failures do
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 300, date: Date.current)

    post opening_balance_path, params: { opening_balance: { actual: 300 } }

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to be_present
    expect(user.categories.exists?(name: "Opening Balance")).to be false
    expect(app_balance).to eq(300)
  end

  # BigDecimal(str, exception: false) is what stands between a blank or malformed submit and a
  # 500: `config.browser_validations` is off app-wide, so nothing but this guard stops a bare POST
  # (or an emptied field) from reaching the server with a figure Ruby cannot parse.
  it "refuses a blank or unparsable figure instead of raising", :aggregate_failures do
    post opening_balance_path, params: { opening_balance: { actual: "" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("Enter a real balance")

    post opening_balance_path, params: { opening_balance: { actual: "1,000" } }
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("Enter a real balance")

    expect(user.categories.exists?(name: "Opening Balance")).to be false
  end

  # THE LATCH IS CASE-INSENSITIVE, matching `Category`'s own uniqueness validation
  # (`case_sensitive: false`). A user who already has a category spelled "opening balance" — legal
  # through the ordinary categories screen — must read as already-latched rather than sail past an
  # exact-case check and crash on `create!`'s own uniqueness refusal.
  it "treats a differently-cased existing category as the latch, not a crash", :aggregate_failures do
    create(:category, :expense, user: user, pool: main, name: "opening balance")

    post opening_balance_path, params: { opening_balance: { actual: 1000 } }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("already")
    expect(user.categories.where(category_type: :income).count).to eq(0)
  end

  # NO MAIN ACCOUNT: reachable by a crafted POST (the card itself never renders without one), and
  # refused before the balance math runs rather than crashing on `PoolCalculator.new(nil)`.
  it "refuses when the user has no main account", :aggregate_failures do
    user.update!(default_account: nil)

    post opening_balance_path, params: { opening_balance: { actual: 1000 } }

    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("main account")
    expect(user.categories.exists?(name: "Opening Balance")).to be false
  end

  # THE CORRECTION IS BOOKKEEPING, NOT THIS PERIOD'S INCOME: `categories.tracked` defaults to
  # true, and the dashboard's tracked totals sum by it — years of untracked history landing as
  # `tracked: true` would inflate this period's income or expense figures by the correction alone.
  it "creates the category untracked, so it does not inflate this period's totals" do
    post opening_balance_path, params: { opening_balance: { actual: 1000 } }

    expect(user.categories.find_by(name: "Opening Balance")).not_to be_tracked
  end

  # THE POT, AND ALLOCATING MONEY DOES NOT MOVE IT (two-ledger spec §2, Task 6).
  #
  # THIS EXAMPLE USED TO PIN THE FAMILY TOTAL — `Pool#total`, unallocated cash PLUS every envelope
  # housed inside main — because money an envelope inside main was holding had not left the bank
  # account, and a bare buffer would have "corrected" main down by exactly what the envelope held.
  # The gate is `AccountLedger#pot` now, and the hazard it was written for cannot recur: a category
  # is not inside an account, and an allocation is an act of intention rather than of location, so
  # the physical ledger never sees it at all.
  #
  # SAME FIXTURE IN THE NEW SHAPE, and the same arithmetic has to come out: $1,000 of income with
  # $150 already claimed by Groceries, a bank statement reading $1,200. The correction is $200, main
  # ends at $1,200, and the PURPOSE side still partitions the same total — $1,050 available plus
  # $150 held.
  it "corrects against the pot, which money already claimed by a category does not lower",
     :aggregate_failures do
       income = create(:category, :income, user: user, pool: main, name: "Pay")
       create(:entry, item: create(:item, category: income), amount: 1000, date: Date.current)
       groceries = create(:category, :expense, :funded, user: user, name: "Groceries")
       create(:allocation, kind: :allocation, to_category: groceries, amount: 150, date: Date.current)

       post opening_balance_path, params: { opening_balance: { actual: 1200 } }

       ledger = CategoryLedger.new([groceries], user: user)
       expect(AccountLedger.new(user).pot).to eq(1200)
       expect(ledger.available + ledger.holding_of(groceries)).to eq(1200)
       expect(user.categories.exists?(name: "Opening Balance")).to be true
     end

  # WHERE THE CORRECTION IS DATED (Henry's ruling of 2026-08-20, from real use). It used to be
  # stamped `Date.current`, which put years of untracked history INSIDE the period the user is
  # standing in — and `tracked: false` does not save it there, because the reader that matters on
  # the Distribute screen (`PoolCalculator#income_within`) sums by DATE and pool, not by
  # `categories.tracked`. So the entry is backdated to the day BEFORE the user's earliest entry:
  # before all history, inside no period anyone will ever distribute.
  #
  # IT STILL LANDS IN MAIN, which is an ACCOUNT and has no start-date gate on the categories that
  # point at it, so `Σ pools == the bank balance` is untouched by the move — the two examples above
  # that measure the balance are unchanged and still read the corrected figure.
  describe "where the correction is dated", :aggregate_failures do
    # PLANTED ON BOTH SIDES OF THE BOUNDARY: the oldest entry is what the correction has to get in
    # front of, and the newest is what proves it is the OLDEST that decides rather than the latest.
    it "dates it the day before the user's earliest entry" do
      income = create(:category, :income, user: user, pool: main, name: "Pay")
      item = create(:item, category: income)
      create(:entry, item: item, amount: 300, date: Date.current - 90.days)
      create(:entry, item: item, amount: 120, date: Date.current - 3.days)

      post opening_balance_path, params: { opening_balance: { actual: 1000 } }

      expect(correction_entry.date.to_date).to eq(Date.current - 91)
    end

    # NO HISTORY AT ALL — a brand-new account whose first act is the correction. There is no
    # earliest entry to get in front of, so today is the honest date and there is no period of
    # history for it to pollute.
    it "dates it today when the user has no entries" do
      post opening_balance_path, params: { opening_balance: { actual: 1000 } }

      expect(correction_entry.date.to_date).to eq(Date.current)
    end

    # THE CONSEQUENCE THE RULING IS ABOUT, at the reader the Distribute screen actually uses:
    # `DistributionPresenter#income_this_period_from` is
    # `account.calculator(today:).income_within(user.period_datetimes_containing(today))`, spelled
    # here exactly as it is spelled there rather than re-derived.
    #
    # BOTH DIRECTIONS ON ONE LITERAL. $50 arrives inside the current period and $300 arrived 60
    # days before it; the correction closes a $650 gap. Dated today, that $650 read as income the
    # user was about to split — $700 on a screen whose whole job is "what came in this period".
    # Backdated, the figure is the $50 that actually came in.
    it "does not count as this period's income on the Distribute screen" do
      user.update!(period_cadence: :biweekly, period_anchor_date: Date.current)
      income = create(:category, :income, user: user, pool: main, name: "Pay")
      item = create(:item, category: income)
      create(:entry, item: item, amount: 300, date: Date.current - 60.days)
      create(:entry, item: item, amount: 50, date: Date.current)

      post opening_balance_path, params: { opening_balance: { actual: 1000 } }

      expect(correction_entry.amount).to eq(650)
      expect(this_periods_income).to eq(50)
    end

    def this_periods_income
      main.reload.calculator(today: Date.current).income_within(user.period_datetimes_containing(Date.current))
    end
  end

  # SUB-CENT INPUT ROUNDS AWAY BEFORE THE COMPARISON (fix round 1 — LOW-1). Without rounding,
  # "0.001" against a zero balance is a non-zero difference that reaches `Entry#amount`'s decimal
  # column, which itself rounds the write down to zero and fails `greater_than: 0` — an unhandled
  # `RecordInvalid` (422) from a figure that, in any currency this app understands, IS zero.
  # `.round(2)` on the parsed input makes the comparison agree with what the column would do
  # anyway, so this takes the ordinary zero-difference path instead.
  it "rounds a sub-cent figure to zero rather than crashing on it", :aggregate_failures do
    post opening_balance_path, params: { opening_balance: { actual: "0.001" } }

    expect(response).to redirect_to(root_path)
    expect(flash[:notice]).to be_present
    expect(user.categories.exists?(name: "Opening Balance")).to be false
  end
end
