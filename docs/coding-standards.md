# Coding Standards

This document defines the architecture, patterns, and coding conventions for the SeriouslyBroke Rails application.

## Core Domain Models

- **User** → has_many Categories, SavingsPools
- **Category** (expense/income/savings types) → has_many Items, has_one Budget
- **Item** → has_many Entries
- **Entry** → the actual transaction record
- **SavingsPool** → goal tracking with target amounts
- **Budget** → period-based spending limits (expense categories only)

## Custom Patterns

### Presenter Pattern (`app/presenters/`)

Uses Ruby `Data.define` for immutable value objects. Controllers instantiate presenters that pre-compute view data.

```ruby
# Controller
@presenter = WeeklyCalendarPresenter.new(user: current_user, date: params[:date])
# View
@presenter.entries_for_day(date)
```

### Calculator Pattern (`app/services/`)

Memoized service objects for computing metrics. Accessed via model method:

```ruby
category.calculator(date).budget_percentage
category.calculator(date).top_items
```

### Searchable System (Custom DSL)

Models define searchable fields, controllers apply searches automatically. See `docs/searchable-system-reference.md` for complete documentation.

```ruby
# Model
class Entry < ApplicationRecord
  include ModelSearchable
  searchable :description, label: "Description"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
end

# Controller
include Searchable
entries = apply_search(entries, { q: params[:q], field: params[:field] })
```

### DateContext Concern (`app/controllers/concerns/date_context.rb`)

Session-based month/year selection. Provides `selected_month`, `selected_year`, `selected_date` helpers.

### EntryType Value Object (`app/models/entry_type.rb`)

Centralizes type configuration (label, color, sign). Use `EntryType[:expense].color` instead of hardcoding.

## View Conventions

- Standardized page header: `render 'shared/page_header'` with title, breadcrumbs, search, actions
- Use `page_header` helper for cleaner syntax
- Tailwind with custom colors from `custom.css` (check available colors before using)
- Squared edges aesthetic (avoid `rounded-lg`, `rounded-xl`)

## Key Principles

### Fat Models, Skinny Controllers

Controllers should be 5-7 lines per action. Extract logic to models, services, or presenters.

- Controllers handle HTTP concerns only: params, session, redirects, renders
- Business logic belongs in models, service objects, form objects, or dedicated classes
- Question any controller action exceeding 10-15 lines of logic
- Look for conditionals in controllers that should be model methods
- Callbacks and validations belong in models, not controllers

### Leverage Existing Code

Before writing new methods, search exhaustively for existing functionality in models, Rails built-ins, and gems.

- **Did we reinvent the wheel?** Search the codebase for existing methods, concerns, or classes that could have been used or extended
- **Could this be a configuration change instead of new code?** Rails often has built-in ways to achieve things
- **Are there existing patterns in this codebase that weren't followed?** Look at similar features for established conventions
- **Did we extend existing abstractions or create competing ones?**

### RESTful Resources

Prefer standard CRUD actions. When tempted to add custom actions, consider if a new nested resource is more appropriate.

- Resources should map to standard CRUD actions: index, show, new, create, edit, update, destroy
- Custom actions are a code smell - consider if a new resource would be more appropriate
- Nested resources should reflect domain relationships
- Avoid verb-based routes; prefer noun-based resources

### Minimal Code

Every new line must be justified. Prefer extending existing methods over creating new ones.

- Don't add features, refactor code, or make "improvements" beyond what was asked
- A bug fix doesn't need surrounding code cleaned up
- A simple feature doesn't need extra configurability
- Don't add docstrings, comments, or type annotations to code you didn't change
- Only add comments where the logic isn't self-evident

### DRY (Don't Repeat Yourself)

- Extract repeated logic into concerns, modules, or base classes
- Use partials for repeated view code
- Create helper methods for repeated view logic
- Look for similar code patterns across the diff that could be unified
- Question any copy-pasted code blocks

### Convention Over Configuration

- Follow Rails naming conventions religiously (plural controllers, singular models, snake_case files)
- Use standard directory structures - don't create custom organizational schemes without strong justification
- Leverage Rails' built-in helpers, concerns, and patterns before creating custom solutions
- Respect RESTful routing conventions
- Use Rails' form helpers, not custom form building

## Code Organization Guidelines

### File & Method Sizing

- **Are there walls of code?** Methods exceeding 15-20 lines need scrutiny
- **Are files appropriately sized?** Not too large (god objects) nor too fragmented (over-abstraction)
- **Is the purpose of each file/class/method immediately clear from its name and structure?**
- **Would a new developer understand this code without extensive context?**

### Rails-Specific Concerns

- Are scopes used appropriately in models?
- Are callbacks used judiciously and not hiding critical business logic?
- Is N+1 query potential addressed with includes/preload/eager_load?
- Are strong parameters properly configured?
- Are validations comprehensive and in the right place?
- Is the database schema reflected properly in migrations?
