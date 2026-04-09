---
name: system-test-writer
description: "Write system tests for Rails features following the project's page-based testing structure. Use this skill whenever the user asks to write tests, create specs, add test coverage, or test a feature they just built. Also use when the user wants to update or add to testing standards. Triggers on: 'write tests for', 'add specs', 'test coverage for', 'create system tests', 'I just finished implementing X' (when tests are the next step), 'update testing guidelines', or any mention of writing RSpec system tests."
---

# System Test Writer

Write minimal, focused, and maintainable Ruby on Rails system tests using RSpec, Capybara, and FactoryBot.

## Before Writing Any Test

1. Look at 2-3 existing tests in `spec/system/` that are similar to what you're writing — match their style
2. Read the implementation code you're testing so you know what user-visible behavior to cover
3. For detailed examples of every pattern below, read `references/examples.md`

## Philosophy

Write the fewest lines of test code that meaningfully verify the feature works. Each test should justify its existence — if removing it wouldn't reduce confidence in the feature, it shouldn't be there.

- **One concept per `it` block** — test one logical behavior, not one DOM element
- **Test what users see and do**, not implementation details
- **Extract repeated actions** into `private` helper methods at the bottom of the file
- **Use `:aggregate_failures` at the describe block level** so multiple expectations can live in one test without masking failures — apply to describe blocks, not individual `it` blocks
- **Factories over fixtures** — use traits and associations to keep setup minimal

## File Organization

Tests mirror the web application's page structure. Each page gets a folder, then tests are split by page section.

```
spec/system/
  feature_name/        # by model/feature (e.g., categories/) or app section (e.g., dashboard/)
    index/             # one folder per page
      header_spec.rb   # one file per page section
      cards_spec.rb
      filtering_spec.rb
    show/
      content_spec.rb
      actions_spec.rb
    new/
      form_spec.rb
    edit/
      form_spec.rb
```

**Naming**: `spec/system/feature_or_section/page/section_spec.rb`
- Keep names short: `header_spec.rb` not `header_functionality_spec.rb`
- Group by model/feature (`categories/`, `items/`) or app section (`dashboard/`, `reports/`)
- Keep related functionality together — form display, validation, submission, and navigation all go in `new/form_spec.rb`
- Test delete functionality in `show/actions_spec.rb` where the delete button lives

## Test Template

```ruby
# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FeatureName PageName SectionName", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
    visit the_relevant_path
  end

  describe "primary functionality", :aggregate_failures do
    it "does the main thing" do
      expect(page).to have_content("Expected Content")
    end
  end

  private

  def perform_common_action
    # extracted helper for repeated DOM interactions
  end
end
```

## Authentication

Always use Devise's `sign_in` helper:

```ruby
before do
  sign_in user
  visit the_path
end
```

## Setup Patterns

### `let!` vs `before` blocks

Use `let!` when the variable is referenced by name in expectations. Use `before` blocks when objects are only needed for setup/context and won't be directly referenced.

```ruby
# Good: main subject referenced in expectations
let!(:category) { create(:category, name: "Groceries", user: user) }

before do
  # Background data not referenced by name
  create(:item, category: category)
  visit category_path(category)
end

it "shows category name" do
  expect(page).to have_content(category.name)  # using the let! variable
end
```

### Factory Randomization

Factories should use Faker and randomization by default. Only specify exact values in tests when verifying specific calculations.

```ruby
# Factory: random by default
factory :item do
  name { Faker::Commerce.product_name }
  description { Faker::Lorem.sentence }
end

# Test: specific values only when testing calculations
before do
  create_list(:entry, 3, item: savings_item, amount: 200.0)
end
it "shows correct balance" do
  expect(page).to have_content("$600.00")
end
```

## Validation Testing

### Client-side (HTML5)
```ruby
it "prevents submission with invalid email format" do
  fill_in "Email", with: "invalid-email"
  expect(page).to have_css("input[type=email]:invalid")
end
```

### Server-side
```ruby
it "shows error for missing name" do
  click_button "Create Category"
  expect(page).to have_content("Name can't be blank")
end
```

## Form Interactions

Use `within("form")` to scope form interactions:
```ruby
within("form") do
  fill_in "Email", with: email
  fill_in "Password", with: password
  click_button "Sign up"
end
```

## Rubocop Compliance

The project enforces these RSpec-specific limits:

- **`RSpec/ExampleLength`**: Max 10 lines per example — split long tests into focused ones
- **`RSpec/MultipleMemoizedHelpers`**: Max 8 helpers per describe — move setup data to `before` blocks
- **`RSpec/IndexedLet`**: Use descriptive names (`groceries_item`) not indexed (`item1`, `item2`)

Strategies to stay within limits:
- Group related object creation in `before` blocks
- Extract complex setup into private helper methods
- Only use `let!` for variables referenced by name in expectations

## What NOT to Do

- Don't write a separate test for every element — group related checks with `:aggregate_failures`
- Don't duplicate test logic — extract to a private helper
- Don't test framework behavior (Rails validations work)
- Don't use brittle selectors that break when markup changes
- Don't create test data not used by the test
- Don't separate form validation/submission/navigation into different files
- Don't use `:aggregate_failures` on individual `it` blocks — put it on the `describe`
- Don't use generic indexed names like `item1`, `item2`
- Don't put setup in `it` blocks — use `before` and `let!`

## Workflow

1. **Examine** existing similar tests for patterns
2. **Plan** the test file location based on the page-based structure
3. **Write** minimal, focused tests
4. **Review** your own output for DRY opportunities and unnecessary lines
5. **Run** the test file individually: `bundle exec rspec path/to/new_spec.rb` (never run entire directories or full suite)
6. **Run** `bundle exec rubocop path/to/new_spec.rb` to check compliance
