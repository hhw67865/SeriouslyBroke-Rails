# frozen_string_literal: true

# The tracking half of these seeds sprinkles `rand` through its entries, and several of
# those categories are linked to pools — so the balance, and therefore the Home row STATE,
# of a seeded pool changed on every replant. A demo screen you cannot reproduce is a demo
# screen nobody can review against. Seeded once here, deliberately, so `db:seed:replant`
# lands on the same figures every time.
srand(20_260_815)

# Clear existing data
Rails.logger.debug "Clearing existing data..."
# Delete in the correct order to avoid foreign key violations.
# PoolMovement leads: its FKs to both pools and entries are non-cascading, so any movement
# on the table makes Entry.delete_all and Pool.delete_all violate them.
[PoolMovement, Entry, Item, Budget, Category, Pool, User].each do |model|
  Rails.logger.debug { "Deleting #{model.name} records..." }
  model.delete_all
end

# Create users
Rails.logger.debug "Creating users..."
user1 = User.create!(
  email: "demo@example.com",
  password: "password123",
  name: "Demo User",
  timezone: "America/New_York"
)

# Define category structure with color schemes
Rails.logger.debug "Creating categories for Demo User..."

# Expense categories with realistic colors
expense_categories = [
  { name: "Housing", color: "#E57373" },
  { name: "Transportation", color: "#64B5F6" },
  { name: "Food & Dining", color: "#81C784" },
  { name: "Utilities", color: "#FFD54F" },
  { name: "Entertainment", color: "#BA68C8" },
  { name: "Health", color: "#4DB6AC" },
  { name: "Personal Care", color: "#FF8A65" },
  { name: "Education", color: "#7986CB" },
  { name: "Shopping", color: "#F06292" },
  { name: "Gifts & Donations", color: "#9575CD" }
].map do |attrs|
  user1.categories.create!(attrs.merge(category_type: :expense))
end

# Income categories
income_categories = [
  { name: "Salary", color: "#66BB6A" },
  { name: "Freelance", color: "#26C6DA" },
  { name: "Investments", color: "#42A5F5" },
  { name: "Gifts", color: "#EC407A" },
  { name: "Rental Income", color: "#AB47BC" }
].map do |attrs|
  user1.categories.create!(attrs.merge(category_type: :income))
end

# Savings categories with specific purposes
savings_categories = [
  { name: "Emergency Fund", color: "#5C6BC0" },
  { name: "Vacation", color: "#26A69A" },
  { name: "Home Down Payment", color: "#EF5350" },
  { name: "Retirement", color: "#66BB6A" },
  { name: "Vehicle", color: "#FFA726" }
].map do |attrs|
  user1.categories.create!(attrs.merge(category_type: :savings))
end

# Create savings pools
Rails.logger.debug "Creating savings pools..."
pools = [
  { name: "Emergency Fund", target_amount: 10_000 },
  { name: "Vacation to Europe", target_amount: 5000 },
  { name: "House Down Payment", target_amount: 50_000 },
  { name: "New Car", target_amount: 15_000 },
  { name: "Retirement Supplement", target_amount: 100_000 }
].map { |attrs| user1.pools.create!(attrs) }

# Link savings categories to savings pools
savings_categories[0].update(pool: pools[0]) # Emergency Fund
savings_categories[1].update(pool: pools[1]) # Vacation
savings_categories[2].update(pool: pools[2]) # Home Down Payment
savings_categories[3].update(pool: pools[4]) # Retirement
savings_categories[4].update(pool: pools[3]) # Vehicle

# Create expense category items
Rails.logger.debug "Creating expense items..."

# Housing items
housing_items = [
  { name: "Rent" },
  { name: "Home Insurance" },
  { name: "Property Tax" },
  { name: "Maintenance" },
  { name: "Mortgage" }
].map { |attrs| expense_categories[0].items.create!(attrs) }

# Transportation items
transportation_items = [
  { name: "Gas" },
  { name: "Car Insurance" },
  { name: "Public Transit" },
  { name: "Car Maintenance" },
  { name: "Parking" },
  { name: "Rideshare" }
].map { |attrs| expense_categories[1].items.create!(attrs) }

# Food items
food_items = [
  { name: "Groceries" },
  { name: "Dining Out" },
  { name: "Takeout" },
  { name: "Coffee Shops" },
  { name: "Work Lunches" }
].map { |attrs| expense_categories[2].items.create!(attrs) }

# Utilities items
utilities_items = [
  { name: "Electricity" },
  { name: "Water" },
  { name: "Internet" },
  { name: "Phone" },
  { name: "Streaming Services" },
  { name: "Gas" }
].map { |attrs| expense_categories[3].items.create!(attrs) }

# Entertainment items
entertainment_items = [
  { name: "Movies" },
  { name: "Concerts" },
  { name: "Subscriptions" },
  { name: "Hobbies" },
  { name: "Gaming" }
].map { |attrs| expense_categories[4].items.create!(attrs) }

# Link some expense categories to savings pools (pool-covered expenses)
# These represent irregular expenses funded by savings pools, not budgets
Rails.logger.debug "Linking expense categories to savings pools..."
expense_categories.find { |c| c.name == "Health" }.update!(pool: pools[0]) # Health → Emergency Fund
expense_categories.find { |c| c.name == "Education" }.update!(pool: pools[4]) # Education → Retirement Supplement
expense_categories.find { |c| c.name == "Gifts & Donations" }.update!(pool: pools[1]) # Gifts → Vacation to Europe

# Create budgets only for budgetable expense categories (not pool-linked)
Rails.logger.debug "Creating budgets..."
expense_budgets = {
  "Housing" => 1500,
  "Transportation" => 400,
  "Food & Dining" => 600,
  "Utilities" => 300,
  "Entertainment" => 200,
  "Personal Care" => 100,
  "Shopping" => 200
}

expense_categories.select(&:budgetable?).each do |category|
  category.create_budget!(
    amount: expense_budgets[category.name] || rand(100..1000),
    prorated: ["Groceries", "Entertainment", "Shopping"].include?(category.name)
  )
end

# Create income items
Rails.logger.debug "Creating income items..."
income_items = {
  "Salary" => [{ name: "Primary Job" }],
  "Freelance" => [
    { name: "Web Development" },
    { name: "Writing" },
    { name: "Consulting" }
  ],
  "Investments" => [
    { name: "Dividends" },
    { name: "Interest" },
    { name: "Capital Gains" }
  ],
  "Gifts" => [
    { name: "Birthday" },
    { name: "Holiday" }
  ],
  "Rental Income" => [
    { name: "Property Rental" }
  ]
}

income_categories.each do |category|
  income_items[category.name].each do |item_attrs|
    category.items.create!(item_attrs)
  end
end

# Create savings items
Rails.logger.debug "Creating savings items..."
savings_items = {
  "Emergency Fund" => [
    { name: "Monthly Contribution" }
  ],
  "Vacation" => [
    { name: "Vacation Savings" }
  ],
  "Home Down Payment" => [
    { name: "Home Savings" }
  ],
  "Retirement" => [
    { name: "Additional Retirement" }
  ],
  "Vehicle" => [
    { name: "Car Fund" }
  ]
}

savings_categories.each do |category|
  savings_items[category.name].each do |item_attrs|
    category.items.create!(item_attrs)
  end
end

# Generate entries for the current and previous month
Rails.logger.debug "Creating entries for the current and previous month..."

# Define months for entries
current_month = Date.current.beginning_of_month
previous_month = 1.month.ago.beginning_of_month
months = [previous_month, current_month]

# Create expense entries for both months
months.each do |month_start|
  month_name = month_start.strftime("%B %Y")

  # Housing expenses
  housing_entries = {
    "Rent" => { amount: 1500, day: 1 },
    "Home Insurance" => month_start.month == 1 ? { amount: 1200, day: 15 } : nil, # January only
    "Property Tax" => (month_start.month % 3).zero? ? { amount: 900, day: 20 } : nil, # Quarterly
    "Maintenance" => { amount: rand(50..200), day: rand(1..28) }
  }

  housing_items.each do |item|
    entry_data = housing_entries[item.name]
    next unless entry_data

    item.entries.create!(
      amount: entry_data[:amount],
      date: month_start + entry_data[:day].days,
      description: "#{item.name} payment for #{month_name}"
    )
  end

  # Transportation expenses - more frequent entries
  transportation_entries = {
    "Gas" => [
      { amount: rand(40..60), day: rand(1..7) },
      { amount: rand(40..60), day: rand(8..14) },
      { amount: rand(40..60), day: rand(15..21) },
      { amount: rand(40..60), day: rand(22..28) }
    ],
    "Car Insurance" => [
      { amount: 120, day: 15 }
    ],
    "Public Transit" => [
      { amount: 25, day: 5 },
      { amount: 25, day: 19 }
    ],
    "Car Maintenance" => month_start == current_month ? [{ amount: 230, day: 12 }] : [],
    "Parking" => [
      { amount: 45, day: 1 }
    ],
    "Rideshare" => [
      { amount: rand(15..30), day: rand(1..7) },
      { amount: rand(15..30), day: rand(8..14) },
      { amount: rand(15..30), day: rand(15..21) },
      { amount: rand(15..30), day: rand(22..28) }
    ]
  }

  transportation_items.each do |item|
    entry_list = transportation_entries[item.name] || []
    entry_list.each do |entry_data|
      item.entries.create!(
        amount: entry_data[:amount],
        date: month_start + entry_data[:day].days,
        description: "#{item.name} expense on #{(month_start + entry_data[:day].days).strftime("%b %d")}"
      )
    end
  end

  # Food expenses - weekly entries
  weekly_food_amounts = {
    "Groceries" => [120, 130, 115, 125],
    "Dining Out" => [45, 65, 70, 50],
    "Takeout" => [35, 30, 40, 25],
    "Coffee Shops" => [18, 22, 20, 15],
    "Work Lunches" => [45, 40, 50, 35]
  }

  food_items.each do |item|
    amounts = weekly_food_amounts[item.name] || [25, 25, 25, 25]

    4.times do |week|
      day = (week * 7) + rand(1..6)
      next if day > 28 # Skip if past end of month

      item.entries.create!(
        amount: amounts[week],
        date: month_start + day.days,
        description: "#{item.name} for week #{week + 1} of #{month_name}"
      )
    end
  end

  # Utilities - monthly
  utilities_dates = {
    "Electricity" => 5,
    "Water" => 10,
    "Internet" => 15,
    "Phone" => 20,
    "Streaming Services" => 25,
    "Gas" => 7
  }

  utilities_amounts = {
    "Electricity" => rand(80..110),
    "Water" => rand(40..60),
    "Internet" => 65,
    "Phone" => 85,
    "Streaming Services" => 35,
    "Gas" => rand(30..70)
  }

  utilities_items.each do |item|
    day = utilities_dates[item.name] || rand(1..15)
    amount = utilities_amounts[item.name] || rand(30..100)

    item.entries.create!(
      amount: amount,
      date: month_start + day.days,
      description: "#{item.name} bill for #{month_name}"
    )
  end

  # Entertainment expenses
  entertainment_entries = {
    "Movies" => [
      { amount: rand(15..30), day: rand(5..15) },
      { amount: rand(15..30), day: rand(20..27) }
    ],
    "Concerts" => month_start == current_month ? [{ amount: 120, day: 18 }] : [],
    "Subscriptions" => [{ amount: 50, day: 5 }],
    "Hobbies" => [{ amount: rand(30..80), day: rand(1..28) }],
    "Gaming" => month_start == previous_month ? [{ amount: 70, day: 12 }] : []
  }

  entertainment_items.each do |item|
    entry_list = entertainment_entries[item.name] || []
    entry_list.each do |entry_data|
      item.entries.create!(
        amount: entry_data[:amount],
        date: month_start + entry_data[:day].days,
        description: "#{item.name} expense on #{(month_start + entry_data[:day].days).strftime("%b %d")}"
      )
    end
  end

  # Income entries - show month-to-month changes
  income_multiplier = month_start == current_month ? 1.05 : 1.0 # 5% increase in current month

  # Salary - consistent monthly
  salary_item = income_categories[0].items.find_by(name: "Primary Job")
  salary_amount = 4500 * income_multiplier
  salary_item.entries.create!(
    amount: salary_amount.round,
    date: month_start + 1.day,
    description: "Monthly salary for #{month_name}"
  )

  # Freelance - varied
  freelance_category = income_categories[1]

  if month_start == current_month
    # More freelance work this month
    freelance_category.items.find_by(name: "Web Development").entries.create!(
      amount: 1200,
      date: month_start + 8.days,
      description: "Web project payment"
    )

    freelance_category.items.find_by(name: "Writing").entries.create!(
      amount: 400,
      date: month_start + 15.days,
      description: "Article series payment"
    )
  else
    # Less freelance work last month
    freelance_category.items.find_by(name: "Web Development").entries.create!(
      amount: 800,
      date: month_start + 12.days,
      description: "Small website project"
    )
  end

  # Investments - quarterly for some items
  investments_category = income_categories[2]

  # For dividends (paid every 3 months)
  if (month_start.month % 3).zero?
    investments_category.items.find_by(name: "Dividends").entries.create!(
      amount: 350,
      date: month_start + 20.days,
      description: "Quarterly dividend payment"
    )
  end

  # Monthly interest
  investments_category.items.find_by(name: "Interest").entries.create!(
    amount: 25,
    date: month_start + 28.days,
    description: "Monthly interest on savings"
  )

  # Savings contributions
  savings_categories.each do |category|
    item = category.items.first

    amount = case category.name
             when "Emergency Fund"
               200
             when "Vacation"
               150
             when "Home Down Payment"
               500
             when "Retirement"
               300
             when "Vehicle"
               250
             else
               100
             end

    # Some variation between months
    amount_adjustment = month_start == current_month ? 1.0 : 0.9

    item.entries.create!(
      amount: (amount * amount_adjustment).round,
      date: month_start + 3.days,
      description: "Monthly contribution to #{category.name}"
    )
  end
end

Rails.logger.debug "Creating entries for other expense categories..."

# Add some entries for remaining expense categories
remaining_expense_categories = expense_categories[5..9] # Health, Personal Care, Education, Shopping, Gifts

months.each do |month_start|
  month_name = month_start.strftime("%B %Y")

  remaining_expense_categories.each do |category|
    # Create a few items if not already present
    if category.items.empty?
      3.times do |i|
        category.items.create!(
          name: "#{category.name} Item #{i + 1}"
        )
      end
    end

    # Create 2-4 entries for each item
    category.items.each do |item|
      entry_count = rand(1..3)

      entry_count.times do |_i|
        item.entries.create!(
          amount: rand(15..150),
          date: month_start + rand(1..28).days,
          description: "#{item.name} expense for #{month_name}"
        )
      end
    end
  end
end

# ---------------------------------------------------------------------------------------
# Envelope budgeting: the data Home is built to explain.
#
# Before this section the demo user had five savings pools and NO account, so Home opened on
# "You're covered this period · $0.00 stays in your buffer" above five rows reading "nothing
# can fund it". Every figure was correct — an account-less pool can genuinely be funded by
# nothing — and it was still a screen no real user should ever see, because the app had never
# been seeded with the shape it exists to render.
#
# So: one account, the savings pools moved inside it, a declared period, a typical income,
# and one budget pool in each of the six row states from the UI design spec §4.4. Every
# figure below is deliberate; see the comment on each pool for how its state arises.
# ---------------------------------------------------------------------------------------
Rails.logger.debug "Creating the budgeting account, its envelopes and one pool per row state..."

# The user's OWN today, not `Date.current`. Every request runs inside the user's timezone
# (ApplicationController sets it), so Home computes against the New York date while a seed
# run late in the evening computes against the UTC one — a day apart. Seeded with the UTC
# date, the Dentist bill below anchored a day late and the period boundary landed INSIDE
# its window, so the pool the state exists to demonstrate rendered as something else
# entirely on the very screen this data exists for.
today = Time.find_zone!(user1.timezone).today

# The anchor is today, so today is a period boundary. That is what makes the Dentist bill
# below genuinely unreachable: no boundary falls between tomorrow and its due date.
user1.update!(period_cadence: :biweekly, period_anchor_date: today, typical_income: 2_400)

checking = user1.pools.create!(name: "Checking", pool_type: :account, target_amount: 2_000)

# Four of the five savings pools move into the account. The fifth is left where it was, on
# purpose: an account-less savings pool is the ordinary shape until Plan 3's backfill, and
# it is the only way to see Home's "No account" band — a pool nothing can fund, owed but
# never a shortfall — on a real screen.
#
# Priorities put them BELOW the envelopes rather than at the default 0: priority is the
# order a distribution fills, and a savings goal funded ahead of rent is not a budget
# anybody runs.
pools.first(4).each_with_index { |pool, index| pool.update!(account: checking, priority: 7 + index) }
orphan_pool = pools[4]
orphan_pool.update!(priority: 11)
Budget.create!(pool: orphan_pool, amount: 150, basis: :per_paycheck)

# The tracking half charges Health, Gifts and Education to three of these pools as
# "pool-covered" expenses and never funds them, which left all three reading `overdrawn` on
# Home — three of the loudest rows on the screen, caused by nothing the budgeting half did
# and drowning out the states this data exists to show. A lump contribution puts each back
# in the black, which is what a user spending out of a savings pool would have done first.
{ "Emergency Fund" => 1_200, "Vacation" => 900, "Retirement" => 1_000 }.each do |category_name, amount|
  category = savings_categories.find { |c| c.name == category_name }
  category.items.first.entries.create!(
    amount: amount,
    date: today,
    description: "Lump contribution to #{category.pool.name}"
  )
end

# What the account actually holds. The tracking half's salary entries belong to categories
# with no pool, so they are income in the reports and cash in no account — this is the one
# deposit Checking can see.
paycheck = user1.categories.create!(name: "Paycheck", category_type: :income, color: "#66BB6A", pool: checking)
paycheck.items.create!(name: "Direct Deposit").entries.create!(
  amount: 3_200,
  date: today,
  description: "Paycheck deposited to Checking"
)

envelope = lambda do |name, priority|
  user1.pools.create!(name: name, pool_type: :budget, account: checking, priority: priority)
end

fund = lambda do |pool, amount|
  PoolMovement.create!(from_pool: checking, to_pool: pool, amount: amount, date: Time.current)
end

# on track — a bill accumulating on schedule. Funded in full already, so it asks for
# nothing this period and its row reads as the quietest thing on the screen.
rent = envelope.call("Rent", 1)
Budget.create!(pool: rent, amount: 1_500, interval_months: 1, anchor_date: today + 2.months)
fund.call(rent, 1_500)

# overdue — the date passed with no payment recorded against the item. An item is what makes
# a rule payable, and therefore what makes it late: without one the app assumes it was paid.
utilities = envelope.call("Utilities", 2)
utility_bills = user1.categories.create!(
  name: "Utility Bills",
  category_type: :expense,
  color: "#FFD54F",
  pool: utilities
)
Budget.create!(
  pool: utilities,
  item: utility_bills.items.create!(name: "Electric Bill"),
  amount: 120,
  interval_months: 1,
  anchor_date: today - 10.days
)

# won't make it — $300 due in three days with no period boundary between tomorrow and then.
# No amount of future funding reaches it; only moving money already held can.
dentist = envelope.call("Dentist", 3)
Budget.create!(pool: dentist, amount: 300, anchor_date: today + 3.days)

# behind — a six-monthly premium with nothing in it yet. Reachable, but the steady schedule
# says it should already hold part of the $1,200, and that lag is what the row names.
car_insurance = envelope.call("Car Insurance", 4)
Budget.create!(pool: car_insurance, amount: 1_200, interval_months: 6, anchor_date: today + 3.months)

# overdrawn — $100 in the envelope and $180 spent out of it. The debt is real and belongs to
# the envelope, not to the account, which is why Checking stays healthy above it.
dining = envelope.call("Dining Out", 5)
Budget.create!(pool: dining, amount: 150, basis: :per_paycheck)
dining_spending = user1.categories.create!(
  name: "Dining Out Spending",
  category_type: :expense,
  color: "#81C784",
  pool: dining
)
dining_item = dining_spending.items.create!(name: "Restaurants")
[[110, 6], [70, 2]].each do |amount, days_ago|
  dining_item.entries.create!(amount: amount, date: today - days_ago.days, description: "Dinner out")
end
fund.call(dining, 100)

# left to spend — a rate envelope, topped back up every period. The only state that shows a
# number you may actually spend.
groceries = envelope.call("Groceries", 6)
Budget.create!(pool: groceries, amount: 400, basis: :per_paycheck)
fund.call(groceries, 400)

Rails.logger.debug "Seed data created successfully!"
