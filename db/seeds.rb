# Clear existing data
puts "Clearing existing data..."
[User, Category, Item, Budget, Entry, SavingsPool].each(&:delete_all)

# Create users
puts "Creating users..."
user1 = User.create!(
  email: "demo@example.com",
  password: "password123",
  name: "Demo User"
)

user2 = User.create!(
  email: "test@example.com",
  password: "password123",
  name: "Test User"
)

# Create categories for user1
puts "Creating categories for Demo User..."
expense_categories = [
  { name: "Housing", color: "#FF6B6B" },
  { name: "Transportation", color: "#4ECDC4" },
  { name: "Food", color: "#45B7D1" },
  { name: "Utilities", color: "#96CEB4" },
  { name: "Entertainment", color: "#FFEEAD" }
].map { |attrs| user1.categories.create!(attrs.merge(category_type: :expense)) }

income_categories = [
  { name: "Salary", color: "#2ECC71" },
  { name: "Freelance", color: "#3498DB" }
].map { |attrs| user1.categories.create!(attrs.merge(category_type: :income)) }

savings_categories = [
  { name: "Emergency Fund", color: "#9B59B6" },
  { name: "Vacation", color: "#E67E22" }
].map { |attrs| user1.categories.create!(attrs.merge(category_type: :savings)) }

# Create savings pools
puts "Creating savings pools..."
savings_pools = [
  { name: "Emergency Fund", target_amount: 10000 },
  { name: "Vacation Fund", target_amount: 5000 }
].map { |attrs| user1.savings_pools.create!(attrs) }

# Create items
puts "Creating items..."
housing_items = [
  { name: "Rent", frequency: :monthly },
  { name: "Home Insurance", frequency: :yearly },
  { name: "Maintenance", frequency: :monthly }
].map { |attrs| expense_categories[0].items.create!(attrs) }

transportation_items = [
  { name: "Gas", frequency: :monthly },
  { name: "Car Insurance", frequency: :yearly },
  { name: "Public Transit", frequency: :monthly }
].map { |attrs| expense_categories[1].items.create!(attrs) }

food_items = [
  { name: "Groceries", frequency: :monthly },
  { name: "Dining Out", frequency: :monthly },
  { name: "Takeout", frequency: :monthly }
].map { |attrs| expense_categories[2].items.create!(attrs) }

# Create budgets
puts "Creating budgets..."
expense_categories.each do |category|
  category.create_budget!(
    amount: rand(500..2000),
    period: :month
  )
end

# Create entries for the last 3 months
puts "Creating entries..."
3.times do |month_offset|
  date = month_offset.months.ago.beginning_of_month
  
  # Housing entries
  housing_items.each do |item|
    amount = case item.name
             when "Rent" then 1500
             when "Home Insurance" then 1200
             when "Maintenance" then rand(100..500)
             end
    
    item.entries.create!(
      amount: amount,
      date: date + rand(1..15).days,
      description: "#{item.name} payment for #{date.strftime('%B %Y')}"
    )
  end

  # Transportation entries
  transportation_items.each do |item|
    amount = case item.name
             when "Gas" then rand(100..300)
             when "Car Insurance" then 800
             when "Public Transit" then 100
             end
    
    item.entries.create!(
      amount: amount,
      date: date + rand(1..15).days,
      description: "#{item.name} payment for #{date.strftime('%B %Y')}"
    )
  end

  # Food entries
  food_items.each do |item|
    amount = case item.name
             when "Groceries" then rand(300..600)
             when "Dining Out" then rand(100..300)
             when "Takeout" then rand(50..150)
             end
    
    item.entries.create!(
      amount: amount,
      date: date + rand(1..15).days,
      description: "#{item.name} payment for #{date.strftime('%B %Y')}"
    )
  end
end

# Create some income entries
puts "Creating income entries..."
income_categories.each do |category|
  item = category.items.create!(name: "Main Income", frequency: :monthly)
  
  3.times do |month_offset|
    date = month_offset.months.ago.beginning_of_month
    item.entries.create!(
      amount: 5000,
      date: date + rand(1..5).days,
      description: "Salary for #{date.strftime('%B %Y')}"
    )
  end
end

puts "Seed data created successfully!"
