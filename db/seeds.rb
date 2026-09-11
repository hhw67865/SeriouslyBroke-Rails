# frozen_string_literal: true

# A demo household on a fortnightly grid: four accounts, income landing in checking, every
# rule shape, savings targets, transfers, and adjustments. Log in as demo@example.com / password123.
# Split into one method per step so each stays small enough for rubocop's size cops without a disable.
class DemoHousehold
  def initialize(timezone)
    @timezone = timezone
  end

  def plant
    Time.use_zone(@timezone) do
      reset!
      create_user!
      create_accounts!
      create_categories!
      create_items!
      create_rules!
      create_savings_targets!
      log_entries!
      create_transfers_and_adjustments!
      report
    end
  end

  private

  def reset!
    [Adjustment, SavingsTarget, Rule, Transfer, Entry, Item, Category, Account, User].each(&:delete_all)
  end

  def create_user!
    @user = User.create!(email: "demo@example.com", password: "password123", name: "Demo User", timezone: @timezone)
    @today = Time.find_zone!(@user.timezone).today
    @user.update!(period_cadence: :biweekly, period_anchor_date: @today)
    @demo_start = periods_ago(14)
  end

  def create_accounts!
    @checking = Account.open(@user, name: "Checking", balance: 1_800)
    @ally = Account.open(@user, name: "Ally Savings", balance: 4_200)
    @brokerage = Account.open(@user, name: "Brokerage", balance: 12_750)
    Account.open(@user, name: "Health Savings", balance: 900)
    @brokerage.update!(keeps_extra: false)
  end

  def create_categories!
    @salary = category("Salary", :income, "#66BB6A")
    @freelance = category("Freelance", :income, "#26C6DA")
    @gifts = category("Gifts", :income, "#EC407A", regular: false)
    @rent = category("Rent", :expense, "#E57373", priority: 1)
    @utilities = category("Utilities", :expense, "#FFD54F", priority: 2)
    @dentist = category("Dentist", :expense, "#F48FB1", priority: 3)
    @car_insurance = category("Car Insurance", :expense, "#9575CD", priority: 4)
    @dining = category("Dining Out", :expense, "#81C784", priority: 5)
    @groceries = category("Groceries", :expense, "#8BC34A", priority: 6)
    @pet_care = category("Pet Care", :expense, "#A1887F", priority: 7)
    @vacation = category("Vacation to Europe", :expense, "#FF8A65", priority: 8)
    @coffee = category("Coffee", :expense, "#795548")
  end

  def create_items!
    @paycheck = item(@salary, "Paycheck")
    @contract = item(@freelance, "Contract work")
    @birthday = item(@gifts, "Birthday")
    @rent_item = item(@rent, "Monthly Rent")
    @electric = item(@utilities, "Electric Bill")
    @internet = item(@utilities, "Internet")
    @restaurants = item(@dining, "Restaurants")
    @supermarket = item(@groceries, "Supermarket")
    @pet_food = item(@pet_care, "Pet Food")
    @vet = item(@pet_care, "Vet")
    @flights = item(@vacation, "Flights & Hotels")
    @cafe = item(@coffee, "Cafe")
  end

  def create_rules!
    rule(@rent, item: @rent_item, amount: 1_500, interval_months: 1, anchor_date: @today + 10, rule_type: :bill)
    rule(@utilities, item: @electric, amount: 118, interval_months: 1, anchor_date: @today - 10)
    rule(@dentist, amount: 300, anchor_date: @today + 3, rule_type: :bill)
    # Started inside its current six-month cycle: a bill's due dates run back to its start, and
    # nothing was paid before this one.
    rule(@car_insurance, amount: 1_200, interval_months: 6, anchor_date: @today + 1.month, rule_type: :bill, starts_on: @today - 4.months)
    rule(@dining, amount: 100, rule_type: :choice)
    rule(@groceries, amount: 400)
    rule(@pet_care, amount: 60, keeps_unspent: true)
    rule(@pet_care, item: @vet, amount: 180, anchor_date: @today + 20, rule_type: :bill)
    rule(@vacation, amount: 5_000, anchor_date: @demo_start + (14 * 78) - 1, rule_type: :choice)
  end

  def create_savings_targets!
    @ally.savings_targets.create!(amount: 150, starts_on: @demo_start)
    @ally.savings_targets.create!(item: @paycheck, percent: 5, starts_on: @demo_start)
    @brokerage.savings_targets.create!(item: @paycheck, percent: 15, starts_on: periods_ago(4))
  end

  def log_entries!
    (0..13).each do |cycle|
      payday = log_regular_entries(cycle)
      log_biweekly_entries(cycle, payday)
    end
    log(@birthday, 200, @today - 30, "From Mom")
    log(@flights, 620, @today - 40, "Deposit on flights")
  end

  # The five things that land every period, whoever's turn it is. Returns payday so the
  # every-other-period entries below can anchor to the same date.
  def log_regular_entries(cycle)
    payday = periods_ago(14 - cycle)
    log(@paycheck, 2_050, payday, "Fortnightly pay")
    log(@supermarket, 180, payday + 2)
    log(@supermarket, 165, payday + 9)
    log(@restaurants, 45, payday + 5)
    log(@cafe, 12, payday + 1)
    log(@pet_food, 38, payday + 4)
    payday
  end

  # The things that land every other period: the contract invoice on even cycles, the bills on odd ones.
  def log_biweekly_entries(cycle, payday)
    log(@contract, 400, payday + 3, "Invoice") if cycle.even?
    log(@electric, 118, payday + 1) if cycle.odd?
    log(@internet, 60, payday + 1) if cycle.odd?
    log(@rent_item, 1_500, payday + 1) if cycle.odd?
  end

  def create_transfers_and_adjustments!
    (1..13).each { |cycle| Transfer.create!(from_account: @checking, to_account: @ally, amount: 250, date: periods_ago(14 - cycle) + 1) }
    Transfer.create!(from_account: @checking, to_account: @brokerage, amount: 300, date: @today - 7)
    Adjustment.create!(source: Rule.find_by!(category: @vacation, item_id: nil), amount: 250, date: @today - 3)
    Adjustment.create!(source: Rule.find_by!(category: @dining, item_id: nil), amount: -20, date: @today - 1)
    Adjustment.create!(source: @ally, amount: -50, date: @today - 2)
  end

  def report
    Rails.logger.debug do
      "Seeded #{@user.email}: #{Account.count} accounts, #{Category.count} categories, #{Entry.count} entries, " \
        "#{Rule.count} rules, #{SavingsTarget.count} savings targets"
    end
  end

  def periods_ago(cycle) = @today - (cycle * 14)
  def category(name, type, color, **attributes) = @user.categories.create!(name: name, category_type: type, color: color, **attributes)
  def item(cat, name) = cat.items.create!(name: name)
  def rule(cat, **attributes) = Rule.create!(category: cat, starts_on: @demo_start, rule_type: :usage, **attributes)
  def log(holder, amount, on, description = nil) = holder.entries.create!(amount: amount, date: on, description: description)
end

DemoHousehold.new("America/New_York").plant
