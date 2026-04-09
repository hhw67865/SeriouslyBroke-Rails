# Detailed Test Examples

This file contains comprehensive examples for every test pattern used in the project. Read this when you need to see the full shape of a test file.

## Table of Contents
- [Type Filtering Spec](#type-filtering-spec)
- [Cards Spec](#cards-spec)
- [Form Spec (New)](#form-spec-new)
- [Header Spec](#header-spec)
- [Actions Spec (Show)](#actions-spec-show)
- [Navigation Spec](#navigation-spec)
- [Empty State Spec](#empty-state-spec)
- [Aggregate Failures Pattern](#aggregate-failures-pattern)
- [Helper Methods Pattern](#helper-methods-pattern)
- [Complex Setup Strategies](#complex-setup-strategies)
- [Search Patterns](#search-patterns)

---

## Type Filtering Spec

`spec/system/categories/index/type_filtering_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Type Filtering", type: :system do
  let(:user) { create(:user) }
  let!(:income_categories) { create_list(:category, 3, category_type: "income", user: user) }
  let!(:expense_categories) { create_list(:category, 2, category_type: "expense", user: user) }

  before { sign_in user }

  describe "type-based filtering", :aggregate_failures do
    it "shows income categories when income type selected" do
      visit categories_path(type: "income")
      expect(page).to have_content("Income Categories")
      income_categories.each do |category|
        expect(page).to have_content(category.name)
      end
      expense_categories.each do |category|
        expect(page).not_to have_content(category.name)
      end
    end

    it "shows expense categories when expense type selected" do
      visit categories_path(type: "expense")
      expect(page).to have_content("Expense Categories")
      expense_categories.each do |category|
        expect(page).to have_content(category.name)
      end
    end

    it "shows all categories when no type specified" do
      visit categories_path
      (income_categories + expense_categories).each do |category|
        expect(page).to have_content(category.name)
      end
    end
  end
end
```

## Cards Spec

`spec/system/categories/index/cards_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Cards", type: :system do
  let(:user) { create(:user) }
  let!(:category) { create(:category, name: "Test Category", category_type: "income", user: user) }

  before do
    sign_in user
    visit categories_path(type: "income")
  end

  describe "category card display", :aggregate_failures do
    it "shows correct category information" do
      expect(page).to have_content(category.name)
      expect(page).to have_content(category.category_type.titleize)
    end
  end

  describe "card interactions", :aggregate_failures do
    it "navigates to category show page when clicked" do
      click_on category.name
      expect(page).to have_current_path(category_path(category))
      expect(page).to have_content(category.name)
    end
  end
end
```

## Form Spec (New)

`spec/system/categories/new/form_spec.rb`

Keep form display, validation, submission, and navigation all in one file.

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories New - Form", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
    visit new_category_path
  end

  describe "form display", :aggregate_failures do
    it "shows all form elements" do
      expect(page).to have_field("Name")
      expect(page).to have_select("Category type")
      expect(page).to have_button("Create Category")
    end

    it "shows navigation elements" do
      expect(page).to have_link("Back to Categories")
    end
  end

  describe "form validation", :aggregate_failures do
    it "shows error for missing name" do
      click_button "Create Category"
      expect(page).to have_content("Name can't be blank")
    end
  end

  describe "successful submission", :aggregate_failures do
    it "creates category and redirects to show page" do
      fill_in "Name", with: "New Category"
      select "Income", from: "Category type"
      click_button "Create Category"
      expect(page).to have_content("Category was successfully created")
      expect(page).to have_current_path(category_path(Category.last))
    end
  end

  describe "navigation", :aggregate_failures do
    it "returns to index when clicking back" do
      click_link "Back to Categories"
      expect(page).to have_current_path(categories_path)
    end
  end
end
```

## Header Spec

`spec/system/categories/index/header_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Header", type: :system do
  let(:user) { create(:user) }
  let!(:categories) { create_list(:category, 3, category_type: "income", user: user) }

  before do
    sign_in user
    visit categories_path(type: "income")
  end

  describe "page header elements", :aggregate_failures do
    it "shows correct title and subtitle" do
      expect(page).to have_content("Income Categories")
      expect(page).to have_content("Manage your categories and track progress")
    end

    it "shows create button" do
      expect(page).to have_link("New Category")
    end
  end

  describe "search functionality", :aggregate_failures do
    it "performs search correctly" do
      searchable_category = create(:category, name: "Coffee Expenses", category_type: "income", user: user)
      visit categories_path(type: "income")
      fill_in "q", with: "Coffee"
      click_button "Search"
      expect(page).to have_content("Coffee Expenses")
    end

    it "handles empty search results" do
      fill_in "q", with: "NonexistentCategory"
      click_button "Search"
      expect(page).to have_content("No categories found")
    end
  end

  describe "create button navigation", :aggregate_failures do
    it "navigates to new category page" do
      click_link "New Category"
      expect(page).to have_current_path(new_category_path)
    end
  end
end
```

## Actions Spec (Show)

`spec/system/categories/show/actions_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Actions", type: :system do
  let(:user) { create(:user) }
  let!(:category) { create(:category, name: "Test Category", user: user) }

  before do
    sign_in user
    visit category_path(category)
  end

  describe "action buttons", :aggregate_failures do
    it "shows edit and delete buttons" do
      expect(page).to have_link("Edit Category")
      expect(page).to have_button("Delete Category")
    end
  end

  describe "edit navigation", :aggregate_failures do
    it "navigates to edit page" do
      click_link "Edit Category"
      expect(page).to have_current_path(edit_category_path(category))
    end
  end

  describe "delete functionality", :aggregate_failures do
    it "deletes category with confirmation" do
      accept_confirm { click_button "Delete Category" }
      expect(page).to have_current_path(categories_path)
      expect(page).to have_content("Category was successfully deleted")
    end
  end
end
```

## Navigation Spec

`spec/system/categories/index/navigation_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Navigation", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
    visit categories_path(type: "income")
  end

  describe "type switching", :aggregate_failures do
    it "switches between category types" do
      click_link "Expense Categories"
      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Expense Categories")
    end
  end
end
```

## Empty State Spec

`spec/system/categories/index/empty_state_spec.rb`

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Empty State", type: :system do
  let(:user) { create(:user) }

  before { sign_in user }

  describe "when no categories exist", :aggregate_failures do
    before { visit categories_path(type: "income") }

    it "shows empty state message" do
      expect(page).to have_content("No income categories found")
      expect(page).to have_content("Create your first category")
    end

    it "provides link to create first category" do
      click_link "Create your first category"
      expect(page).to have_current_path(new_category_path)
    end
  end
end
```

## Aggregate Failures Pattern

Always apply `:aggregate_failures` at the describe block level, not on individual `it` blocks.

```ruby
# GOOD: describe-level
describe "form validation", :aggregate_failures do
  it "shows error for missing name" do
    # test code...
  end

  it "shows error for duplicate name" do
    # test code...
  end
end

# BAD: it-level
describe "form validation" do
  it "shows error for missing name", :aggregate_failures do
    # test code...
  end

  it "shows error for duplicate name", :aggregate_failures do
    # test code...
  end
end
```

## Helper Methods Pattern

Extract repeated form filling and DOM interactions into private methods with default parameters:

```ruby
RSpec.describe "Authentication - Sign Up", type: :system do
  let(:valid_email) { "test@example.com" }
  let(:valid_password) { "password123" }

  before { visit new_user_registration_path }

  describe "successful submission", :aggregate_failures do
    it "completes sign up successfully" do
      fill_sign_up_form
      within("form") { click_button "Sign up" }
      expect(page).to have_content("Welcome! You have signed up successfully.")
      expect(page).to have_current_path(authenticated_root_path)
    end
  end

  private

  def fill_sign_up_form(email: valid_email, password: valid_password, confirmation: nil)
    within("form") do
      fill_in "Email", with: email
      fill_in "Password", with: password
      fill_in "Password confirmation", with: confirmation || password
    end
  end
end
```

## Complex Setup Strategies

### Strategy 1: Group related objects in before blocks

```ruby
describe "monthly budget calculations", :aggregate_failures do
  let!(:expense_category) { create(:category, category_type: "expense", user: user) }
  let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }

  before do
    create(:budget, category: expense_category, amount: 1000)
    create(:entry, item: groceries_item, amount: 100, date: base_date)
    create(:entry, item: dining_item, amount: 50, date: base_date)
    visit categories_path(type: "expense", month: base_date.month, year: base_date.year)
  end
end
```

### Strategy 2: Extract setup to helper methods

```ruby
describe "complex scenario testing", :aggregate_failures do
  let!(:expense_category) { create(:category, category_type: "expense", user: user) }

  before do
    setup_monthly_budget_data(expense_category)
    visit categories_path(type: "expense")
  end

  private

  def setup_monthly_budget_data(category)
    create(:budget, category: category, amount: 1000)
    # Create all necessary test data
  end
end
```

## Search Patterns

### Simple search

```ruby
describe "search functionality", :aggregate_failures do
  it "searches by name" do
    searchable = create(:category, name: "Coffee Shop", category_type: "expense", user: user)
    create(:category, name: "Salary", category_type: "expense", user: user)
    visit categories_path(type: "expense")
    fill_in "q", with: "Coffee"
    click_button "Search"
    expect(page).to have_content("Coffee Shop")
    expect(page).not_to have_content("Salary")
  end
end
```

### Advanced search with field selector

```ruby
describe "advanced search functionality", :aggregate_failures do
  let!(:entry) { create(:entry, description: "Coffee purchase") }

  before { visit entries_path }

  it "searches by description field" do
    select "Description", from: "field"
    fill_in "q", with: "Coffee"
    click_button "Search"
    expect(page).to have_content("Coffee purchase")
  end

  it "updates placeholder when field changes" do
    select "Date", from: "field"
    expect(page).to have_field("q", placeholder: "Search by date...")
  end
end
```

### Search state preservation

```ruby
it "preserves other filters during search" do
  visit categories_path(type: "expense")
  fill_in "q", with: "Coffee"
  click_button "Search"
  expect(page).to have_current_path(categories_path(type: "expense", q: "Coffee"))
end
```
