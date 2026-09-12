# frozen_string_literal: true

require "rails_helper"
require Rails.root.glob("db/migrate/*_convert_pools_to_accounts.rb").sole

# Every example rewinds the data migration (which restores main's shape without data), plants
# main-shaped rows through anonymous table classes, runs the migration forward, and reads the
# result through today's models. The example transaction rolls the DDL back afterwards.
RSpec.describe ConvertPoolsToAccounts do
  let(:migration) { described_class.new }
  let(:pools) { legacy("savings_pools") }
  let(:categories) { legacy("categories") }
  let(:items) { legacy("items") }
  let(:entries) { legacy("entries") }
  let(:rules) { legacy("rules") }
  let(:now) { Time.utc(2026, 9, 9, 12, 0) }

  def expense = 0
  def income = 1
  def savings = 2

  def legacy(table) = Class.new(ApplicationRecord) { self.table_name = table }

  def step(direction)
    migration.suppress_messages { migration.migrate(direction) }
    [User, Account, Transfer, Category, Item, Entry, Rule, Adjustment].each(&:reset_column_information)
  end

  before { step(:down) }
  after { [User, Account, Transfer, Category, Item, Entry, Rule, Adjustment].each(&:reset_column_information) }

  def convert = step(:up)

  def plant_user(timezone: nil) = create(:user, timezone: timezone)

  def plant_pool(user, name, start_date: nil)
    pools.create!(user_id: user.id, name: name, start_date: start_date, created_at: now, updated_at: now)
  end

  def plant_category(user, name, type, pool: nil)
    categories.create!(
      user_id: user.id,
      name: name,
      category_type: type,
      savings_pool_id: pool&.id,
      tracked: true,
      created_at: now,
      updated_at: now
    )
  end

  def plant_entry(category, amount, at:)
    item = items.create!(category_id: category.id, name: "Item #{SecureRandom.hex(3)}", created_at: now, updated_at: now)
    entries.create!(item_id: item.id, amount: amount, date: at, created_at: now, updated_at: now)
  end

  def plant_budget(category, amount, created_at:)
    rules.create!(category_id: category.id, amount: amount, prorated: false, created_at: created_at, updated_at: created_at)
  end

  it "gives every user a main Checking account opened the day before their first entry", :aggregate_failures do
    user = plant_user
    salary = plant_category(user, "Salary", income)
    plant_entry(salary, 1000, at: Time.utc(2026, 3, 10, 12))

    convert

    main = user.reload.main_account
    expect(main.name).to eq("Checking")
    expect(main.opened_on).to eq(Date.new(2026, 3, 9))
    expect(main.opening_balance).to eq(0)
  end

  it "opens a user with no entries on the run date" do
    user = plant_user

    travel_to(now) { convert }

    expect(user.reload.main_account.opened_on).to eq(Date.new(2026, 9, 9))
  end

  it "turns each savings pool into an account, opened on its start date, even with no categories", :aggregate_failures do
    user = plant_user
    plant_pool(user, "Vacation", start_date: Date.new(2026, 1, 1))
    plant_pool(user, "Empty pool")

    convert

    vacation = user.reload.accounts.find_by!(name: "Vacation")
    expect(vacation.opened_on).to eq(Date.new(2026, 1, 1))
    expect(user.accounts.find_by!(name: "Empty pool").opened_on).to eq(user.main_account.opened_on)
    expect(user.accounts.count).to eq(3)
  end

  it "opens a pool's account no later than the first savings entry it received", :aggregate_failures do
    user = plant_user
    late = plant_pool(user, "Late", start_date: Date.new(2026, 6, 1))
    early = plant_pool(user, "Early", start_date: Date.new(2026, 1, 1))
    plant_entry(plant_category(user, "Late saving", savings, pool: late), 100, at: Time.utc(2026, 2, 1, 12))
    plant_entry(plant_category(user, "Early saving", savings, pool: early), 100, at: Time.utc(2026, 2, 1, 12))

    convert

    expect(user.accounts.find_by!(name: "Late").opened_on).to eq(Date.new(2026, 2, 1))
    expect(user.accounts.find_by!(name: "Early").opened_on).to eq(Date.new(2026, 1, 1))
  end

  it "turns savings entries into transfers from main into the pool's account and deletes the category", :aggregate_failures do
    user = plant_user
    saving = plant_category(user, "Vacation saving", savings, pool: plant_pool(user, "Vacation", start_date: Date.new(2026, 1, 1)))
    plant_entry(saving, 200, at: Time.utc(2026, 2, 1, 12))
    plant_entry(saving, 50, at: Time.utc(2026, 3, 1, 12))

    convert

    vacation = user.reload.accounts.find_by!(name: "Vacation")
    expect(Transfer.where(from_account: user.main_account, to_account: vacation).order(:date).pluck(:date, :amount)).to eq([[Date.new(2026, 2, 1), 200], [Date.new(2026, 3, 1), 50]])
    expect(Category.where(user: user, name: "Vacation saving")).not_to exist
    expect([Item.count, Entry.count]).to eq([0, 0])
    expect(AccountLedger.new(user).balance_of(vacation)).to eq(250)
  end

  it "mints an account named after a savings category that has no pool" do
    user = plant_user
    saving = plant_category(user, "Robinhood", savings)
    plant_entry(saving, 75, at: Time.utc(2026, 4, 1, 12))

    convert

    expect(AccountLedger.new(user.reload).balance_of(user.accounts.find_by!(name: "Robinhood"))).to eq(75)
  end

  it "keeps the total across accounts equal to income minus spending", :aggregate_failures do
    user = plant_user
    plant_entry(plant_category(user, "Salary", income), 3000, at: Time.utc(2026, 5, 1, 12))
    plant_entry(plant_category(user, "Food", expense), 400, at: Time.utc(2026, 5, 2, 12))
    plant_entry(plant_category(user, "Emergency", savings), 1000, at: Time.utc(2026, 5, 3, 12))

    convert

    ledger = AccountLedger.new(user.reload)
    expect(ledger.total_money).to eq(2600)
    expect(ledger.pot).to eq(1600)
    expect(ledger.balance_of(user.accounts.find_by!(name: "Emergency"))).to eq(1000)
  end

  it "suffixes account names that clash", :aggregate_failures do
    user = plant_user
    plant_pool(user, "checking")
    plant_category(user, "Vacation saving", savings, pool: plant_pool(user, "Vacation"))
    plant_category(user, "vacation", savings)

    convert

    expect(user.reload.main_account.name).to eq("Checking 2")
    expect(user.accounts.pluck(:name)).to contain_exactly("checking", "Checking 2", "Vacation", "vacation 2")
  end

  it "returns a pool's own spending to main, from the pool's start date onward", :aggregate_failures do
    user = plant_user
    pool = plant_pool(user, "Vacation", start_date: Date.new(2026, 2, 1))
    spending = plant_category(user, "Vacation spending", expense, pool: pool)
    plant_entry(plant_category(user, "Vacation saving", savings, pool: pool), 500, at: Time.utc(2026, 3, 1, 12))
    plant_entry(spending, 120, at: Time.utc(2026, 3, 5, 12))
    plant_entry(spending, 80, at: Time.utc(2026, 1, 20, 12)) # before the pool opened: never its money

    convert

    ledger = AccountLedger.new(user.reload)
    expect(ledger.balance_of(user.accounts.find_by!(name: "Vacation"))).to eq(380)
    expect([ledger.pot, ledger.total_money]).to eq([-580, -200])
  end

  it "drops the pool link from the categories that survive", :aggregate_failures do
    user = plant_user
    pool = plant_pool(user, "Bills")
    plant_category(user, "Utilities", expense, pool: pool)

    convert

    utilities = Category.find_by!(name: "Utilities")
    expect(utilities.priority).to eq(0)
    expect(utilities).to be_regular
    expect(Category.column_names).not_to include("savings_pool_id")
  end

  it "stamps each rule with its budget's creation day in the user's timezone", :aggregate_failures do
    user = plant_user(timezone: "America/New_York")
    food = plant_category(user, "Food", expense)
    plant_budget(food, 400, created_at: Time.utc(2026, 3, 1, 3, 0))

    convert

    rule = Rule.find_by!(category_id: food.id)
    expect(rule.starts_on).to eq(Date.new(2026, 2, 28))
    expect(rule).to have_attributes(rule_type: "usage", anchor_date: nil, interval_months: nil, keeps_unspent: false, amount: 400)
  end

  it "converts entry timestamps to the user's calendar day, UTC when none is set", :aggregate_failures do
    ny = plant_user(timezone: "America/New_York")
    utc = plant_user
    plant_entry(plant_category(ny, "Food", expense), 10, at: Time.utc(2026, 3, 1, 3, 30))
    plant_entry(plant_category(utc, "Food", expense), 10, at: Time.utc(2026, 3, 1, 3, 30))

    convert

    expect(Entry.joins(item: :category).where(categories: { user_id: ny.id }).pick(:date)).to eq(Date.new(2026, 2, 28))
    expect(Entry.joins(item: :category).where(categories: { user_id: utc.id }).pick(:date)).to eq(Date.new(2026, 3, 1))
    expect(Entry.columns_hash["date"].type).to eq(:date)
  end

  it "puts a day back as local midnight, so a down and up cycle never drifts the date" do
    ny = plant_user(timezone: "America/New_York")
    plant_entry(plant_category(ny, "Food", expense), 10, at: Time.utc(2026, 3, 1, 3, 30))
    convert

    step(:down)
    clear_the_bank
    convert

    expect(Entry.joins(item: :category).where(categories: { user_id: ny.id }).pick(:date)).to eq(Date.new(2026, 2, 28))
  end

  it "refuses a user who already has a main account" do
    plant_user
    convert
    step(:down)

    expect { convert }.to raise_error(described_class::Refused, /already migrated/)
  end

  it "removes main's shape", :aggregate_failures do
    convert

    connection = ActiveRecord::Base.connection
    expect(connection.table_exists?("savings_pools")).to be(false)
    expect(Rule.column_names).not_to include("prorated")
    expect(Entry.column_names).not_to include("day")
    expect(connection.check_constraints("categories").map(&:name)).to include("categories_two_types")
    expect(Entry.columns_hash["date"].null).to be(false)
    expect(Rule.columns_hash["starts_on"].null).to be(false)
  end

  # `down` restores main's shape but keeps the accounts and transfers `up` minted, and `up` refuses
  # a user who already has a main account, so a second run starts from an empty bank.
  def clear_the_bank
    Transfer.delete_all
    Account.delete_all
  end
end
