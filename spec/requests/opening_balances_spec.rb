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

  it "raises main to the entered figure with an income-type correction", :aggregate_failures do
    income = create(:category, :income, user: user, pool: main, name: "Pay")
    create(:entry, item: create(:item, category: income), amount: 300, date: Date.current)

    post opening_balance_path, params: { opening_balance: { actual: 1000 } }

    expect(app_balance).to eq(1000)
    correction = user.categories.find_by(name: "Opening Balance")
    expect(correction).to be_income
    expect(correction.pool).to eq(main)
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
end
