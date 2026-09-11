# Coding Standards

This document defines the architecture, patterns, and coding conventions for the SeriouslyBroke Rails application.

## Core Domain Models

- **User** → has_many Categories, Accounts, Rules (through Categories); belongs_to a main Account
- **Account** → where money sits; balance is a ledger read, never a stored column
- **Category** (expense/income types) → has_many Items, has_many Rules
- **Item** → has_many Entries, has_one Rule
- **Entry** → the actual transaction record; income lands in checking, expenses leave it
- **Rule** → a category or item's claim on main: a period allowance or a dated bill/goal
- **SavingsTarget** → one promise on a savings Account: a fixed amount a period, or a share of an income Item
- **Adjustment** → a signed delta on a Rule's or an Account's claim (a top-up, a reduction or a skip)
- **Transfer** → money moved between two of a user's Accounts

## Custom Patterns

### Presenter Pattern (`app/presenters/`)

Uses Ruby `Data.define` for immutable value objects. Controllers instantiate presenters that pre-compute view data, usually by reading from a ledger or calculator.

```ruby
# Controller
@presenter = HomePresenter.new(user: current_user)
# View
@presenter.troubles
```

### Calculator Pattern (`app/services/`)

Plain service objects, fed a fixed number of queries up front, that compute a figure without touching the database again per call:

```ruby
AccountLedger.new(current_user).balance_of(account)
ClaimCalculator.new(rule).claim
SavingsCalculator.new(account).claim
ClaimLedger.new(current_user).claims
```

`AccountLedger` totals one user's account balances; `ClaimCalculator` computes a single rule's claim on main; `SavingsCalculator` computes a single savings Account's claim on main, the same way for a fixed amount or a share of an item; `ClaimLedger` runs every rule's and every savings account's calculator for a user in a fixed number of queries. `ClaimLedger#claims` is the one list every screen reads — Home, the Savings page, the sacrifice page and the Budget tiles never ask what record is behind a claim.

### Form Object Pattern (`app/services/`)

Plain `ActiveModel::Model` (or plain Ruby) objects that turn form params into a valid record, keeping validation and coercion logic out of controllers:

```ruby
RuleForm.new(current_user, rule_params, rule: @rule).save
AdjustmentForm.new(rule: @rule, params: adjustment_params, name: current_user.name).save
EntryForm.new(current_user, @entry, entry_params)
CadenceChange.new(user: current_user, declaration: declaration_params)
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

### Simplicity-First Frontend

Prefer the simplest solution that works. Escalate complexity only when truly needed:

1. **Pure HTML first** - Use semantic HTML elements (`<details>/<summary>` for toggles, `<dialog>` for modals, etc.)
2. **CSS next** - Many interactions can be CSS-only (`:hover`, `:focus`, transitions)
3. **Turbo Frames/Streams** - For server-rendered partial updates without full page reloads
4. **Stimulus** - Only when client-side state or DOM manipulation is unavoidable

Never reach for Stimulus or JavaScript when HTML or CSS can solve the problem. The goal is maintainable, accessible, progressively-enhanced interfaces.

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
