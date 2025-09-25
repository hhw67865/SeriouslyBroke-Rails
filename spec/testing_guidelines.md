# Testing Guidelines and Patterns

This document serves as a comprehensive reference for how tests should be written in this Rails application. Any LLM or developer working on this codebase should follow these established patterns to maintain consistency and code quality.

## Philosophy

- **Minimal code**: Write tests with as few lines as possible while maintaining clarity
- **System test focus**: Primarily use system tests for end-to-end functionality testing
- **DRY principles**: Extract common actions into private helper methods
- **Clear organization**: Use descriptive contexts and test names
- **Essential functionality focus**: Test the core functionality without over-testing every detail
- **Avoid verbose tests**: Prefer fewer, focused tests over many detailed micro-tests

## File Organization

### Core Concept: Page-Based Testing

The system test structure mirrors your web application's pages. Each **web page** gets its own folder, then we divide tests by **page sections** to keep them focused and manageable.

**Grouping Strategy:**
- **By Model/Feature**: `categories/`, `items/`, `savings_pools/` 
- **By App Section**: `dashboard/`, `reports/`, `admin/`
- **Special Cases**: `authentication/` (can be single file if simple)

### Naming Convention
- System tests: `spec/system/feature_or_section/page/section_spec.rb`
- Examples: 
  - `spec/system/categories/index/header_spec.rb` (categories feature, index page, header section)
  - `spec/system/categories/show/content_spec.rb` (categories feature, show page, content section)
  - `spec/system/dashboard/overview/summary_spec.rb` (dashboard section, overview page, summary section)
- Model tests: `spec/models/model_name_spec.rb`
- Controller tests: `spec/controllers/controller_name_spec.rb`
- **Simple names preferred**: `header_spec.rb` not `header_functionality_spec.rb`
- **Page-based organization**: Each web page gets its own folder, divided by page sections

### Directory Structure
```
spec/
├── system/           # Primary focus - end-to-end tests
│   ├── categories/   # Group by model/feature
│   │   ├── index/    # Categories index page - divide by page sections
│   │   │   ├── header_spec.rb          # Page header (title, search, create button)
│   │   │   ├── cards_spec.rb           # Category cards display & interactions
│   │   │   └── filtering_spec.rb       # Type filtering (income/expense)
│   │   ├── show/     # Category show page - divide by page sections
│   │   │   ├── content_spec.rb         # Category details display
│   │   │   ├── actions_spec.rb         # Edit/delete buttons
│   │   │   └── related_spec.rb         # Related items, associations
│   │   ├── new/      # New category page
│   │   │   └── form_spec.rb            # Complete form (validation, submission, navigation)
│   │   └── edit/     # Edit category page
│   │       └── form_spec.rb            # Complete form (pre-fill, validation, submission, navigation)
│   ├── items/        # Group by model/feature
│   │   ├── index/
│   │   ├── show/
│   │   ├── new/
│   │   └── edit/
│   ├── dashboard/    # Group by app section (not a model)
│   │   ├── overview/ # Dashboard overview page
│   │   │   ├── summary_spec.rb         # Summary cards/widgets
│   │   │   ├── charts_spec.rb          # Chart sections
│   │   │   └── navigation_spec.rb      # Dashboard navigation
│   │   └── reports/  # Dashboard reports page
│   │       ├── filters_spec.rb         # Report filters section
│   │       └── tables_spec.rb          # Report tables section
│   ├── authentication/ # Special case - can be single file or folder
│   │   └── authentication_spec.rb      # Or break into sign_in/, sign_up/ if complex
│   └── navbar_spec.rb  # Global navigation testing (not tied to specific features)
├── models/           # Unit tests for models
├── controllers/      # Controller-specific tests
├── factories/        # FactoryBot definitions
└── support/          # Helper files and configuration
```

## Test Structure Patterns

### Basic System Test Template
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FeatureName", type: :system do
  describe "Action Name" do
    before { visit path_to_page }

    describe "page content", :aggregate_failures do
      it "shows all required elements" do
        expect(page).to have_content("Expected Content")
        expect(page).to have_link("Expected Link")
      end
    end

    context "with valid information" do
      # Valid scenarios
    end

    context "with invalid information" do
      # Invalid scenarios
    end

    describe "navigation", :aggregate_failures do
      it "provides correct navigation links" do
        # Navigation tests
      end
    end
  end
end
```

### Modular Index Test Examples

For complex index pages, break down into focused test files:

#### Type Filtering Spec (`spec/system/categories/index/type_filtering_spec.rb`)
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Type Filtering", type: :system do
  let!(:income_categories) { create_list(:category, 3, category_type: "income") }
  let!(:expense_categories) { create_list(:category, 2, category_type: "expense") }

  describe "type-based filtering" do
    it "shows income categories when income type selected", :aggregate_failures do
      visit categories_path(type: "income")
      
      expect(page).to have_content("Income Categories")
      income_categories.each do |category|
        expect(page).to have_content(category.name)
      end
      expense_categories.each do |category|
        expect(page).not_to have_content(category.name)
      end
    end

    it "shows expense categories when expense type selected", :aggregate_failures do
      visit categories_path(type: "expense")
      
      expect(page).to have_content("Expense Categories")
      expense_categories.each do |category|
        expect(page).to have_content(category.name)
      end
      income_categories.each do |category|
        expect(page).not_to have_content(category.name)
      end
    end

    it "shows all categories when no type specified", :aggregate_failures do
      visit categories_path
      
      (income_categories + expense_categories).each do |category|
        expect(page).to have_content(category.name)
      end
    end
  end
end
```

#### Cards Spec (`spec/system/categories/index/cards_spec.rb`)
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Cards", type: :system do
  let!(:category) { create(:category, name: "Test Category", category_type: "income") }

  before { visit categories_path(type: "income") }

  describe "category card display", :aggregate_failures do
    it "shows correct category information" do
      expect(page).to have_content(category.name)
      expect(page).to have_content(category.category_type.titleize)
      # Add other fields that should be displayed
    end

    it "shows proper styling for category type" do
      expect(page).to have_css(".category-card.income-category") # or whatever CSS classes
    end
  end

  describe "card interactions" do
    it "navigates to category show page when clicked", :aggregate_failures do
      click_on category.name # or click_link depending on implementation
      
      expect(page).to have_current_path(category_path(category))
      expect(page).to have_content(category.name)
    end
  end
end
```

#### Complete Form Spec (`spec/system/categories/new/form_spec.rb`)
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories New - Form", type: :system do
  before { visit new_category_path }

  describe "form display", :aggregate_failures do
    it "shows all form elements" do
      expect(page).to have_field("Name")
      expect(page).to have_select("Category type")
      expect(page).to have_button("Create Category")
    end

    it "shows navigation elements" do
      expect(page).to have_link("Back to Categories")
      expect(page).to have_link("Cancel") # if present
    end
  end

  describe "form validation" do
    it "shows error for missing name", :aggregate_failures do
      click_button "Create Category"
      expect(page).to have_content("Name can't be blank")
    end

    it "shows error for missing category type", :aggregate_failures do
      fill_in "Name", with: "Test Category"
      click_button "Create Category"
      expect(page).to have_content("Category type can't be blank")
    end
  end

  describe "successful submission", :aggregate_failures do
    it "creates category and redirects to show page" do
      fill_in "Name", with: "New Category"
      select "Income", from: "Category type"
      click_button "Create Category"
      
      expect(page).to have_content("Category was successfully created")
      expect(page).to have_current_path(category_path(Category.last))
      expect(page).to have_content("New Category")
    end
  end

  describe "navigation" do
    it "returns to index when clicking back", :aggregate_failures do
      click_link "Back to Categories"
      expect(page).to have_current_path(categories_path)
    end
  end
end
```

#### Header Spec (`spec/system/categories/index/header_spec.rb`)
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Header", type: :system do
  let!(:categories) { create_list(:category, 3, category_type: "income") }

  before { visit categories_path(type: "income") }

  describe "page header elements", :aggregate_failures do
    it "shows correct title and subtitle" do
      expect(page).to have_content("Income Categories")
      expect(page).to have_content("Manage your categories and track progress")
    end

    it "shows create button" do
      expect(page).to have_link("New Category")
    end
  end

  describe "search functionality" do
    it "shows search form", :aggregate_failures do
      expect(page).to have_field("q")
      expect(page).to have_button("Search") # or search icon
    end

    it "performs search correctly", :aggregate_failures do
      searchable_category = create(:category, name: "Coffee Expenses", category_type: "income")
      visit categories_path(type: "income")
      
      fill_in "q", with: "Coffee"
      click_button "Search" # or press Enter
      
      expect(page).to have_content("Coffee Expenses")
      categories.each do |category|
        expect(page).not_to have_content(category.name)
      end
    end

    it "handles empty search results", :aggregate_failures do
      fill_in "q", with: "NonexistentCategory"
      click_button "Search"
      
      expect(page).to have_content("No categories found")
      # or whatever empty state message is displayed
    end

    it "clears search results", :aggregate_failures do
      fill_in "q", with: "Coffee"
      click_button "Search"
      
      fill_in "q", with: ""
      click_button "Search"
      
      categories.each do |category|
        expect(page).to have_content(category.name)
      end
    end
  end

  describe "create button navigation" do
    it "navigates to new category page", :aggregate_failures do
      click_link "New Category"
      
      expect(page).to have_current_path(new_category_path)
      expect(page).to have_content("New Category")
    end
  end
end
```

#### Actions Spec (`spec/system/categories/show/actions_spec.rb`)
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Show - Actions", type: :system do
  let!(:category) { create(:category, name: "Test Category") }

  before { visit category_path(category) }

  describe "action buttons", :aggregate_failures do
    it "shows edit and delete buttons" do
      expect(page).to have_link("Edit Category")
      expect(page).to have_button("Delete Category") # or link
    end
  end

  describe "edit navigation" do
    it "navigates to edit page", :aggregate_failures do
      click_link "Edit Category"
      expect(page).to have_current_path(edit_category_path(category))
      expect(page).to have_content("Edit Category")
    end
  end

  describe "delete functionality" do
    it "deletes category with confirmation", :aggregate_failures do
      accept_confirm do
        click_button "Delete Category"
      end
      
      expect(page).to have_current_path(categories_path)
      expect(page).to have_content("Category was successfully deleted")
      expect(page).not_to have_content("Test Category")
    end
  end
end
```

#### Navigation Spec (`spec/system/categories/index/navigation_spec.rb`)
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Navigation", type: :system do
  before { visit categories_path(type: "income") }

  describe "main navigation", :aggregate_failures do
    it "provides navigation to dashboard" do
      click_link "Dashboard" # within main nav
      expect(page).to have_current_path(authenticated_root_path)
    end

    it "provides navigation to other sections" do
      within ".sidebar" do # or main nav
        expect(page).to have_link("Items")
        expect(page).to have_link("Entries")
        expect(page).to have_link("Savings Pools")
      end
    end
  end

  describe "breadcrumb navigation", :aggregate_failures do
    it "shows correct breadcrumbs" do
      expect(page).to have_link("Home")
      expect(page).to have_link("Categories")
      expect(page).to have_content("Income") # current page indicator
    end
  end

  describe "type switching", :aggregate_failures do
    it "switches between category types" do
      click_link "Expense Categories" # or tab/button for type switching
      expect(page).to have_current_path(categories_path(type: "expense"))
      expect(page).to have_content("Expense Categories")
    end
  end
end
```

#### Empty State Spec (`spec/system/categories/index/empty_state_spec.rb`)
```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Categories Index - Empty State", type: :system do
  describe "when no categories exist" do
    before { visit categories_path(type: "income") }

    it "shows empty state message", :aggregate_failures do
      expect(page).to have_content("No income categories found")
      expect(page).to have_content("Create your first category")
    end

    it "provides link to create first category", :aggregate_failures do
      click_link "Create your first category" # or "New Category"
      expect(page).to have_current_path(new_category_path)
    end
  end

  describe "when search returns no results" do
    let!(:categories) { create_list(:category, 2, category_type: "income") }

    before do
      visit categories_path(type: "income")
      fill_in "q", with: "NonexistentCategory"
      click_button "Search"
    end

    it "shows no results message", :aggregate_failures do
      expect(page).to have_content("No categories found matching")
      expect(page).to have_content("NonexistentCategory")
    end

    it "provides option to clear search", :aggregate_failures do
      click_link "Clear search" # or clear button
      categories.each do |category|
        expect(page).to have_content(category.name)
      end
    end
  end
end
```

### Context Organization
Use contexts to group related test scenarios:
```ruby
context "with valid information" do
  let(:valid_email) { "test@example.com" }
  let(:valid_password) { "password123" }
  
  # Valid scenario tests
end

context "with invalid information" do
  # Invalid scenario tests
end

context "with duplicate email" do
  before { create(:user, email: "test@example.com") }
  
  # Duplicate data tests
end
```

## Code Style Preferences

### Use Aggregate Failures
Group related expectations with `:aggregate_failures`:
```ruby
it "completes sign up successfully", :aggregate_failures do
  fill_sign_up_form
  within("form") { click_button "Sign up" }

  expect(page).to have_content("Welcome! You have signed up successfully.")
  expect(page).to have_current_path(authenticated_root_path)
end
```

### Descriptive Test Names
Write clear, specific test descriptions:
```ruby
# ✅ Good
it "shows error for mismatched password confirmation"
it "signs in successfully"
it "prevents submission with invalid email format"

# ❌ Avoid
it "works"
it "validates password"
```

### Within Blocks for Form Interactions
Use `within("form")` to scope form interactions:
```ruby
within("form") do
  fill_in "Email", with: email
  fill_in "Password", with: password
  click_button "Sign up"
end
```

## Helper Methods and DRY Principles

### Extract Common Actions
Create private helper methods for repeated actions:
```ruby
private

def fill_sign_up_form(email: valid_email, password: valid_password, confirmation: nil)
  within("form") do
    fill_in "Email", with: email
    fill_in "Password", with: password
    fill_in "Password confirmation", with: confirmation || password
  end
end

def sign_in_with_credentials(remember_me: false)
  within("form") do
    fill_in "Email", with: user.email
    fill_in "Password", with: "password123"
    check "Remember me" if remember_me
    click_button "Sign in"
  end
end
```

### Method Parameters with Defaults
Use default parameters for flexible helper methods:
```ruby
def fill_sign_up_form(email: valid_email, password: valid_password, confirmation: nil)
  # Method body
end
```

## Validation Testing Patterns

### Client-Side Validation
Test HTML5 validation using CSS selectors:
```ruby
it "prevents submission with invalid email format" do
  fill_in "Email", with: "invalid-email"
  fill_in "Password", with: "password123"
  fill_in "Password confirmation", with: "password123"
  expect(page).to have_css("input[type=email]:invalid")
end

it "allows form submission with valid email" do
  fill_sign_up_form
  expect(page).not_to have_css("input:invalid")
end
```

### Server-Side Validation
Test server-side validation by checking error messages:
```ruby
it "shows error for short password" do
  fill_in "Email", with: "test@example.com"
  fill_in "Password", with: "123"
  fill_in "Password confirmation", with: "123"
  click_button "Sign up"

  expect(page).to have_content("Password is too short")
end
```

## Key Testing Principles for Page Sections

### Complete Functionality Within Sections
Keep related functionality together rather than fragmenting it:

**✅ Good: Complete Form Testing**
- Form display, validation, submission, and navigation all in `new/form_spec.rb`
- Delete functionality tested in the `show/actions_spec.rb` where the delete button lives

**❌ Avoid: Over-fragmentation**
- Don't separate form display, validation, submission into different files
- Don't create separate folders for delete functionality - test it where the button appears

### Test Condensation Principles

**Focus on Essential Functionality:**
- Test that core features work, not every micro-detail
- Combine related assertions using `:aggregate_failures`
- Avoid testing the same thing multiple ways

**Example: Condensed vs Verbose**
```ruby
# ✅ Good: Condensed, focused testing
describe "type-specific headers", :aggregate_failures do
  it "shows correct content for income categories" do
    visit categories_path(type: "income")
    
    expect(page).to have_content("Income Categories")
    expect(page).to have_content("Track your income sources and monthly earnings")
    expect(page).to have_link("New Income Category")
  end
end

# ❌ Avoid: Over-detailed, verbose testing
describe "income categories header" do
  describe "page header elements", :aggregate_failures do
    it "shows correct income title" do
      expect(page).to have_content("Income Categories")
    end
    
    it "shows correct income subtitle" do
      expect(page).to have_content("Track your income sources and monthly earnings")
    end
    
    it "shows create button for income category" do
      expect(page).to have_link("New Income Category")
    end
  end
  
  describe "create button navigation" do
    # More separate tests for the same functionality...
  end
end
```

**Aggregate Failures Rule:**
- **ALWAYS use `:aggregate_failures`** when a test has multiple `expect` statements
- This shows all failures at once instead of stopping at the first one
- Essential for system tests where multiple elements need to work together

### Navigation Testing Within Page Sections
Test navigation where it naturally occurs within page sections:

**In Header Sections** (`index/header_spec.rb`):
```ruby
describe "create button navigation" do
  it "navigates to new category page", :aggregate_failures do
    click_link "New Category"
    expect(page).to have_current_path(new_category_path)
    expect(page).to have_content("New Category")
  end
end
```

**In Action Sections** (`show/actions_spec.rb`):
```ruby
describe "edit navigation" do
  it "navigates to edit page", :aggregate_failures do
    click_link "Edit Category"
    expect(page).to have_current_path(edit_category_path(category))
  end
end

describe "delete functionality" do
  it "deletes and redirects to index", :aggregate_failures do
    accept_confirm { click_button "Delete Category" }
    expect(page).to have_current_path(categories_path)
    expect(page).to have_content("Category was successfully deleted")
  end
end
```

**In Form Sections** (`new/form_spec.rb`, `edit/form_spec.rb`):
```ruby
describe "navigation" do
  it "returns to index when clicking back", :aggregate_failures do
    click_link "Back to Categories"
    expect(page).to have_current_path(categories_path)
  end
end

describe "successful submission", :aggregate_failures do
  it "creates category and redirects to show page" do
    fill_in "Name", with: "New Category"
    click_button "Create Category"
    
    expect(page).to have_current_path(category_path(Category.last))
    expect(page).to have_content("Category was successfully created")
  end
end
```

## Factory Usage

### Basic Factory Usage
Use FactoryBot for test data creation:
```ruby
# Create a user
let!(:user) { create(:user, email: "test@example.com", password: "password123") }

# Create with specific attributes
before { create(:user, email: "test@example.com") }
```

### Factory in Context Setup
Use factories in before blocks for context-specific data:
```ruby
context "with duplicate email" do
  before { create(:user, email: "test@example.com") }
  
  # Tests that rely on existing user
end
```

## RSpec Feature Usage

### Let and Let!
- Use `let` for lazy-loaded variables
- Use `let!` when you need the variable created immediately

```ruby
let(:valid_email) { "test@example.com" }
let!(:user) { create(:user, email: "test@example.com") }
```

### Before Blocks
Use `before` blocks for setup that applies to multiple tests:
```ruby
describe "Sign in" do
  before { visit new_user_session_path }
  
  # All tests in this block start at the sign-in page
end
```

### Setup Patterns: Keep `it` blocks minimal
- Put data creation and navigation in `before` blocks.
- Only define `let`/`let!` when the variable itself is referenced in expectations; otherwise create it in `before` as a local to avoid unused memoized helpers.
- Standardize navigation (e.g., `visit ...`) in `before` to keep examples focused on assertions.

```ruby
# ✅ Good: Focused example, setup in before
describe "Details card" do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, category_type: "expense", user: user) }

  before do
    sign_in user
    # Background data not referenced by name in expectations
    groceries = create(:item, category: category)
    create(:entry, item: groceries)
    visit category_path(category)
  end

  it "shows accurate counts and created date", :aggregate_failures do
    expect(page).to have_content("Number of Items")
    expect(page).to have_content("1")
    expect(page).to have_content(category.created_at.strftime("%b %d, %Y"))
  end
end

# ❌ Avoid: Inline setup in the example and unused let!s
describe "Details card" do
  let!(:user) { create(:user) }
  let!(:category) { create(:category, category_type: "expense", user: user) }
  let!(:item1) { create(:item, category: category) } # Not referenced by name

  it "shows accurate counts" do
    sign_in user
    create(:entry, item: item1)
    visit category_path(category)
    expect(page).to have_content("1")
  end
end
```

### Shared Setup
For complex setup, use before blocks with specific scoping:
```ruby
before do
  sign_in user
  visit authenticated_root_path
end
```

## Common Test Patterns

### Page Content Verification
Always test that required UI elements are present:
```ruby
describe "page content", :aggregate_failures do
  it "shows all required elements" do
    expect(page).to have_content("Create your account")
    expect(page).to have_content("Start managing your finances today")
    expect(page).to have_link("Back to Home")
    expect(page).to have_link("Already have an account? Sign in")
  end
end
```

### Error Message Testing
Test specific error messages for different validation failures:
```ruby
it "shows error for wrong password" do
  attempt_sign_in(user.email, "wrongpassword")
  expect(page).to have_content("Invalid Email or password")
end
```

### Success Path Testing
Test the happy path with success messages and redirects:
```ruby
it "completes sign up successfully", :aggregate_failures do
  fill_sign_up_form
  within("form") { click_button "Sign up" }

  expect(page).to have_content("Welcome! You have signed up successfully.")
  expect(page).to have_current_path(authenticated_root_path)
end
```

## Testing the Searchable System

This application uses a sophisticated searchable system (see `docs/searchable-system-reference.md`). Here's how to test it effectively:

### Simple Search (Categories Style)
```ruby
describe "search functionality" do
  it "searches by name", :aggregate_failures do
    searchable_category = create(:category, name: "Coffee Shop", category_type: "expense")
    non_matching = create(:category, name: "Salary", category_type: "expense")
    
    visit categories_path(type: "expense")
    fill_in "q", with: "Coffee"
    click_button "Search"
    
    expect(page).to have_content("Coffee Shop")
    expect(page).not_to have_content("Salary")
  end
end
```

### Advanced Search with Field Selector (Entries Style)
```ruby
describe "advanced search functionality" do
  let!(:entry) { create(:entry, description: "Coffee purchase") }
  let!(:item) { create(:item, name: "Coffee") }
  let!(:other_entry) { create(:entry, description: "Salary payment") }

  before { visit entries_path }

  it "searches by description field", :aggregate_failures do
    select "Description", from: "field"
    fill_in "q", with: "Coffee"
    click_button "Search"
    
    expect(page).to have_content("Coffee purchase")
    expect(page).not_to have_content("Salary payment")
  end

  it "searches by item name through association", :aggregate_failures do
    select "Item", from: "field"
    fill_in "q", with: "Coffee"
    click_button "Search"
    
    expect(page).to have_content(entry.description)
  end

  it "updates placeholder when field changes" do
    select "Date", from: "field"
    expect(page).to have_field("q", placeholder: "Search by date...")
    
    select "Item", from: "field"
    expect(page).to have_field("q", placeholder: "Search by item...")
  end
end
```

### Search State Preservation
```ruby
it "preserves other filters during search", :aggregate_failures do
  visit categories_path(type: "expense")
  fill_in "q", with: "Coffee"
  click_button "Search"
  
  expect(page).to have_current_path(categories_path(type: "expense", q: "Coffee"))
  expect(page).to have_content("Expense Categories") # type preserved
end
```

## Key Principles

1. **Modular testing**: Break complex pages into focused test files for better maintainability
2. **Simple naming**: Use basic names like `header_spec.rb`, not `header_functionality_spec.rb`
3. **Condensed testing**: Group related assertions with `:aggregate_failures` rather than separate tests
4. **Essential functionality focus**: Test core features work, avoid micro-testing every detail
5. **Always use `:aggregate_failures`** when tests have multiple expectations
6. **Extract repetitive code** into private helper methods
7. **Use descriptive variable names** that clearly indicate purpose
8. **Test both positive and negative scenarios** for each feature
9. **Focus on user behavior** rather than implementation details
10. **Keep tests independent** - each test should be able to run in isolation
11. **Use meaningful contexts** to group related test scenarios
12. **Test the complete user journey** in system tests
13. **Test navigation thoroughly** - ensure all pages are properly connected

## Anti-Patterns to Avoid

- ❌ **Over-modularization**: Separating form validation, submission, and navigation into different files
- ❌ **Monolithic specs**: Testing everything about a complex page in one giant file
- ❌ **Artificial separation**: Creating separate folders for functionality that belongs together (like delete buttons)
- ❌ **Verbose testing**: Creating separate tests for every tiny detail instead of grouping related functionality
- ❌ **Missing aggregate failures**: Not using `:aggregate_failures` when tests have multiple expectations
- ❌ **Redundant testing**: Testing the same functionality multiple ways unnecessarily
- ❌ Long test methods without helper extraction
- ❌ Testing implementation details instead of user behavior
- ❌ Repetitive form filling without helper methods
- ❌ Tests that depend on other tests running first
- ❌ Vague test descriptions like "it works"
- ❌ Missing validation testing for both client and server side
- ❌ Not testing error conditions and edge cases
- ❌ Verbose file names like `header_functionality_spec.rb` instead of `header_spec.rb`
- ❌ Not testing search functionality thoroughly when using the searchable system
- ❌ Missing navigation tests where buttons/links actually appear

## Rubocop Compliance for RSpec Tests

To maintain code quality and prevent Rubocop violations, follow these specific guidelines for RSpec tests.

### Memoized Helpers Management (`RSpec/MultipleMemoizedHelpers`)

**Current Limit**: 8 helpers per describe block (configured in `.rubocop.yml`)

**✅ Good: Strategic Helper Usage**
```ruby
describe "expense card shows correct monthly budget" do
  let!(:expense_category) { create(:category, category_type: "expense", user: user) }
  let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }
  
  before do
    # Create budget and entries in before block when they're only used for setup
    create(:budget, category: expense_category, amount: 1000)
    create(:entry, item: groceries_item, amount: 100, date: base_date)
    create(:entry, item: dining_item, amount: 50, date: base_date)
    
    visit categories_path(type: "expense")
  end
  
  # Tests here...
end
```

**❌ Avoid: Excessive let! Usage**
```ruby
describe "expense card shows correct monthly budget" do
  let!(:expense_category) { create(:category, category_type: "expense", user: user) }
  let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }
  let!(:budget) { create(:budget, category: expense_category, amount: 1000) }
  let!(:entry1) { create(:entry, item: groceries_item, amount: 100, date: base_date) }
  let!(:entry2) { create(:entry, item: dining_item, amount: 50, date: base_date) }
  let!(:next_month_entry1) { create(:entry, item: groceries_item, amount: 200, date: next_date) }
  let!(:next_month_entry2) { create(:entry, item: dining_item, amount: 100, date: next_date) }
  # 8+ helpers - triggers Rubocop warning
end
```

### When to Use `let!` vs `before` Blocks (`RSpec/LetSetup`)

**Use `let!` when:**
- The object is referenced by name in tests
- You need the object's attributes (id, name, etc.) in expectations
- The object represents the main subject being tested

**Use `before` blocks when:**
- Objects are only needed for setup/context
- Objects won't be directly referenced in test assertions
- Creating multiple related objects for background data

**✅ Good: Proper let! Usage**
```ruby
describe "search with type filtering" do
  let!(:income_category) { create(:category, name: "Freelance Income", category_type: "income", user: user) }
  
  before do
    # Background data that won't be directly referenced
    create(:category, name: "Freelance Tools", category_type: "expense", user: user)
    create(:category, name: "Freelance Savings", category_type: "savings", user: user)
    
    visit categories_path(type: "income")
  end
  
  it "searches within selected category type only" do
    fill_in "q", with: "Freelance"
    find("input[name='q']").send_keys(:return)
    
    expect(page).to have_content(income_category.name) # Using the let! object
    expect(page).not_to have_content("Freelance Tools")
  end
end
```

**❌ Avoid: Unused let! Statements**
```ruby
describe "search functionality" do
  let!(:searchable_income) { create(:category, name: "Freelance Income", user: user) }
  let!(:searchable_expense) { create(:category, name: "Freelance Tools", user: user) }
  
  # If these variables are never referenced by name in tests, use before block instead
  
  it "performs search correctly" do
    fill_in "q", with: "Freelance"
    # Not using searchable_income or searchable_expense variables directly
    expect(page).to have_content("Freelance Income")
  end
end
```

### Example Length Management (`RSpec/ExampleLength`)

**Current Limit**: 10 lines per example (configured in `.rubocop.yml`)

**✅ Good: Split Long Examples into Focused Tests**
```ruby
describe "type filtering" do
  it "shows only income categories when income type selected" do
    visit categories_path(type: "income")
    expect(page).to have_content("Income Categories")
    income_categories.each { |cat| expect(page).to have_content(cat.name) }
  end

  it "shows only expense categories when expense type selected" do
    visit categories_path(type: "expense")
    expect(page).to have_content("Expense Categories")
    expense_categories.each { |cat| expect(page).to have_content(cat.name) }
  end

  it "defaults to expense categories when no type specified" do
    visit categories_path
    expect(page).to have_content("Expense Categories")
  end
end
```

**❌ Avoid: One Long Test with Multiple Scenarios**
```ruby
describe "type filtering" do
  it "shows correct categories for each type" do
    # Test income type
    visit categories_path(type: "income")
    expect(page).to have_content("Income Categories")
    income_categories.each { |cat| expect(page).to have_content(cat.name) }
    
    # Test expense type  
    visit categories_path(type: "expense")
    expect(page).to have_content("Expense Categories")
    expense_categories.each { |cat| expect(page).to have_content(cat.name) }
    
    # Test default
    visit categories_path
    expect(page).to have_content("Expense Categories")
    # 15+ lines - triggers Rubocop warning
  end
end
```

### Meaningful Variable Naming (`RSpec/IndexedLet`)

**✅ Good: Descriptive Names**
```ruby
describe "expense card displays correct information" do
  let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }
  let!(:gas_item) { create(:item, category: expense_category, name: "Gas") }
  
  # Clear what each item represents
end
```

**❌ Avoid: Generic Indexed Names**
```ruby
describe "expense card displays correct information" do
  let!(:item1) { create(:item, category: expense_category, name: "Groceries") }
  let!(:item2) { create(:item, category: expense_category, name: "Dining") }
  let!(:item3) { create(:item, category: expense_category, name: "Gas") }
  
  # Unclear what item1, item2, item3 represent
end
```

### Complex System Test Considerations

**When More Helpers Are Acceptable:**
- System tests that need to set up complex user scenarios
- Tests involving multiple related models (user, categories, items, entries, budgets)
- Month-based testing that requires data across different time periods
- Tests that verify calculations across multiple data points

**Strategies to Stay Within Limits:**
```ruby
# Strategy 1: Group related objects in before blocks
describe "monthly budget calculations" do
  let!(:expense_category) { create(:category, category_type: "expense", user: user) }
  let!(:groceries_item) { create(:item, category: expense_category, name: "Groceries") }
  let!(:dining_item) { create(:item, category: expense_category, name: "Dining") }
  
  before do
    # Group all entries and budget creation together
    create(:budget, category: expense_category, amount: 1000)
    
    # Current month entries
    create(:entry, item: groceries_item, amount: 100, date: base_date)
    create(:entry, item: dining_item, amount: 50, date: base_date)
    
    # Next month entries
    create(:entry, item: groceries_item, amount: 200, date: next_date)
    create(:entry, item: dining_item, amount: 100, date: next_date)
    
    visit categories_path(type: "expense", month: base_date.month, year: base_date.year)
  end
end

# Strategy 2: Extract setup to helper methods
describe "complex scenario testing" do
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

### Configuration Notes

The project's `.rubocop.yml` includes these RSpec-specific settings:

```yaml
# RSpec specific configurations
RSpec/ExampleLength:
  Max: 10

# Allow more memoized helpers for complex system tests  
RSpec/MultipleMemoizedHelpers:
  Max: 8
```

These limits balance code quality with the practical needs of comprehensive system testing. They can be adjusted if consistently needed, but should be increased thoughtfully.

### Quick Rubocop Check Commands

```bash
# Check specific test files
bundle exec rubocop spec/system/categories/index/cards_spec.rb --format simple

# Check all spec files
bundle exec rubocop spec/ --format simple

# Auto-correct simple issues
bundle exec rubocop spec/ --autocorrect

# Check entire project
bundle exec rubocop --format simple
```

This documentation should be updated as new testing patterns emerge in the codebase.
