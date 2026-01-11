# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Development
bin/dev                      # Start Rails server with Tailwind watcher
bin/setup                    # Full environment setup

# Testing
bundle exec rspec            # Run all tests
bundle exec rspec spec/system/calendar/  # Run specific directory
bundle exec rspec spec/system/calendar/index/grid_spec.rb:45  # Run single test

# Code Quality
bundle exec rubocop -A       # Lint with auto-fix
bin/ci                       # Full CI pipeline (style, security, tests, seeds)

# Database
rails db:prepare             # Create/migrate database
rails db:seed:replant        # Reset and re-seed
```

## Documentation

All coding standards and patterns are documented in `/docs/`:

- **`docs/coding-standards.md`** - Architecture, custom patterns (Presenter, Calculator, Searchable), and key principles (Fat Models/Skinny Controllers, DRY, RESTful design)
- **`docs/design-standards.md`** - S-Tier SaaS design checklist (colors, typography, spacing, components, accessibility)
- **`docs/searchable-system-reference.md`** - Complete reference for the searchable DSL system
- **`spec/testing_guidelines.md`** - Comprehensive testing patterns and RSpec conventions

Always consult these files before implementing features to ensure consistency with established patterns.

---

## Development Workflow

### Code Review Workflow

After implementing any Rails code changes, invoke the `rails-code-reviewer` agent for feedback:

1. **Complete your implementation** - Write the feature, bug fix, or refactoring
2. **Run the rails-code-reviewer agent** - This agent analyzes uncommitted changes for:
   - Adherence to Rails conventions (Fat Models, Skinny Controllers)
   - Whether existing abstractions were leveraged before creating new code
   - Code maintainability and DRY principles
   - RESTful design patterns
3. **Address feedback** - Fix any critical issues or suggestions before committing
4. **Commit only after review passes** - Ensures code quality before it enters the repository

This agent should be used proactively after completing significant code changes.

---

## Visual Development

### Design Principles

- Comprehensive design checklist in `/docs/design-standards.md`
- When making visual (front-end, UI/UX) changes, always refer to this file for guidance
- Use Tailwind with custom colors from `custom.css` (check available colors before using)

### Quick Visual Check

IMMEDIATELY after implementing any front-end change:

1. **Identify what changed** - Review the modified components/pages
2. **Navigate to affected pages** - Use `mcp__playwright__browser_navigate` to visit each changed view
3. **Verify design compliance** - Compare against `/docs/design-standards.md`
4. **Validate feature implementation** - Ensure the change fulfills the user's specific request
5. **Check acceptance criteria** - Review any provided context files or requirements
6. **Capture evidence** - Take full page screenshot at desktop viewport (1440px) of each changed view
7. **Check for errors** - Run `mcp__playwright__browser_console_messages`

This verification ensures changes meet design standards and user requirements.

### Comprehensive Design Review

Invoke the `design-review` agent for thorough design validation when:

- Completing significant UI/UX features
- Before finalizing PRs with visual changes
- Needing comprehensive accessibility and responsiveness testing

The design-review agent performs:
- Multi-viewport testing (desktop 1440px, tablet 768px, mobile 375px)
- Interaction and user flow verification
- Accessibility checks (WCAG 2.1 AA compliance)
- Visual polish assessment (alignment, spacing, typography)
- Console error checking

---

## Testing Workflow

### Philosophy

- **Minimal code**: Write tests with as few lines as possible while maintaining clarity
- **System test focus**: Primarily use system tests for end-to-end functionality testing
- **DRY principles**: Extract common actions into private helper methods
- **Essential functionality focus**: Test core functionality without over-testing every detail

### Before Writing Tests

1. **Read the testing guidelines** - Check `/spec/testing_guidelines.md` for project-specific standards
2. **Examine existing tests** - Look at similar tests in `spec/system/` to match established patterns
3. **Understand the feature** - Review the implementation to identify core functionality needing tests

### Test File Organization

Tests follow a strict page-based structure mirroring the web application:

```
spec/system/
├── feature_name/     # Group by model/feature or app section
│   ├── index/        # Index page folder
│   │   ├── header_spec.rb
│   │   ├── cards_spec.rb
│   │   └── filtering_spec.rb
│   ├── show/         # Show page folder
│   ├── new/          # New page folder
│   └── edit/         # Edit page folder
```

### Testing Standards

- Use `:aggregate_failures` at the describe block level for cleaner code
- One concept per test - each `it` block tests one logical behavior
- Extract repeated DOM interactions into private helper methods
- Use factories efficiently with traits and associations
- Test user-visible behavior, not implementation details

### What NOT to Do

- Don't write separate tests for every single element on a page
- Don't duplicate test logic - extract to helpers
- Don't test framework behavior (Rails validations work)
- Don't write overly specific selectors that break easily
- Don't create unnecessary test data

### Running Tests

After implementing features, run relevant tests to verify:

```bash
bundle exec rspec spec/system/feature_name/  # Run feature tests
bundle exec rspec                             # Run all tests
```

---

## Summary: Implementation Checklist

When implementing any feature:

1. **Read documentation** - Consult `/docs/` for standards before coding
2. **Implement the feature** - Follow patterns in `docs/coding-standards.md`
3. **Run rails-code-reviewer** - Get feedback on code quality
4. **Fix issues** - Address any review feedback
5. **If front-end changes** - Perform Quick Visual Check
6. **If significant UI** - Run design-review agent
7. **Write tests** - Follow patterns in `spec/testing_guidelines.md`
8. **Run tests** - Verify implementation with `bundle exec rspec`
9. **Commit** - Only after all checks pass
