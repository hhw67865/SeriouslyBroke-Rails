# frozen_string_literal: true

# Clear existing data
Rails.logger.debug "Clearing existing data..."
# Delete in the correct order to avoid foreign key violations
[Entry, Item, Budget, Category, SavingsPool, User].each do |model|
  Rails.logger.debug { "Deleting #{model.name} records..." }
  model.delete_all
end

# Create users
Rails.logger.debug "Creating users..."
user1 = User.create!(
  email: "demo@example.com",
  password: "password123",
  name: "Demo User"
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
savings_pools = [
  { name: "Emergency Fund", target_amount: 10_000 },
  { name: "Vacation to Europe", target_amount: 5000 },
  { name: "House Down Payment", target_amount: 50_000 },
  { name: "New Car", target_amount: 15_000 },
  { name: "Retirement Supplement", target_amount: 100_000 }
].map { |attrs| user1.savings_pools.create!(attrs) }

# Link savings categories to savings pools
savings_categories[0].update(savings_pool: savings_pools[0]) # Emergency Fund
savings_categories[1].update(savings_pool: savings_pools[1]) # Vacation
savings_categories[2].update(savings_pool: savings_pools[2]) # Home Down Payment
savings_categories[3].update(savings_pool: savings_pools[4]) # Retirement
savings_categories[4].update(savings_pool: savings_pools[3]) # Vehicle

# Create expense category items
Rails.logger.debug "Creating expense items..."

# Housing items
housing_items = [
  { name: "Rent", frequency: :monthly },
  { name: "Home Insurance", frequency: :yearly },
  { name: "Property Tax", frequency: :monthly },
  { name: "Maintenance", frequency: :monthly },
  { name: "Mortgage", frequency: :monthly }
].map { |attrs| expense_categories[0].items.create!(attrs) }

# Transportation items
transportation_items = [
  { name: "Gas", frequency: :monthly },
  { name: "Car Insurance", frequency: :yearly },
  { name: "Public Transit", frequency: :monthly },
  { name: "Car Maintenance", frequency: :monthly },
  { name: "Parking", frequency: :monthly },
  { name: "Rideshare", frequency: :monthly }
].map { |attrs| expense_categories[1].items.create!(attrs) }

# Food items
food_items = [
  { name: "Groceries", frequency: :monthly },
  { name: "Dining Out", frequency: :monthly },
  { name: "Takeout", frequency: :monthly },
  { name: "Coffee Shops", frequency: :monthly },
  { name: "Work Lunches", frequency: :monthly }
].map { |attrs| expense_categories[2].items.create!(attrs) }

# Utilities items
utilities_items = [
  { name: "Electricity", frequency: :monthly },
  { name: "Water", frequency: :monthly },
  { name: "Internet", frequency: :monthly },
  { name: "Phone", frequency: :monthly },
  { name: "Streaming Services", frequency: :monthly },
  { name: "Gas", frequency: :monthly }
].map { |attrs| expense_categories[3].items.create!(attrs) }

# Entertainment items
entertainment_items = [
  { name: "Movies", frequency: :monthly },
  { name: "Concerts", frequency: :monthly },
  { name: "Subscriptions", frequency: :monthly },
  { name: "Hobbies", frequency: :monthly },
  { name: "Gaming", frequency: :monthly }
].map { |attrs| expense_categories[4].items.create!(attrs) }

# Create budget for expense categories
Rails.logger.debug "Creating budgets..."
expense_budgets = {
  "Housing" => 1500,
  "Transportation" => 400,
  "Food & Dining" => 600,
  "Utilities" => 300,
  "Entertainment" => 200,
  "Health" => 250,
  "Personal Care" => 100,
  "Education" => 150,
  "Shopping" => 200,
  "Gifts & Donations" => 100
}

expense_categories.each do |category|
  category.create_budget!(
    amount: expense_budgets[category.name] || rand(100..1000),
    period: :month
  )
end

# Create income items
Rails.logger.debug "Creating income items..."
income_items = {
  "Salary" => [{ name: "Primary Job", frequency: :monthly }],
  "Freelance" => [
    { name: "Web Development", frequency: :monthly },
    { name: "Writing", frequency: :monthly },
    { name: "Consulting", frequency: :monthly }
  ],
  "Investments" => [
    { name: "Dividends", frequency: :yearly },
    { name: "Interest", frequency: :monthly },
    { name: "Capital Gains", frequency: :yearly }
  ],
  "Gifts" => [
    { name: "Birthday", frequency: :yearly },
    { name: "Holiday", frequency: :yearly }
  ],
  "Rental Income" => [
    { name: "Property Rental", frequency: :monthly }
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
    { name: "Monthly Contribution", frequency: :monthly }
  ],
  "Vacation" => [
    { name: "Vacation Savings", frequency: :monthly }
  ],
  "Home Down Payment" => [
    { name: "Home Savings", frequency: :monthly }
  ],
  "Retirement" => [
    { name: "Additional Retirement", frequency: :monthly }
  ],
  "Vehicle" => [
    { name: "Car Fund", frequency: :monthly }
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

  # Entertainment expenses - varied frequency
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

  # For dividends (paid every 3 months, but using yearly frequency)
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
          name: "#{category.name} Item #{i + 1}",
          frequency: [:monthly, :yearly].sample
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

Rails.logger.debug "Seed data created successfully!"
