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

# Tailwind CSS
bin/rails tailwindcss:build  # Rebuild CSS (required when adding new utility classes)
```

## Documentation

All coding standards and patterns are documented in `/docs/`:

- **`docs/coding-standards.md`** - Architecture, custom patterns (Presenter, Calculator, Searchable), and key principles (Fat Models/Skinny Controllers, DRY, RESTful design)
- **`docs/design-standards.md`** - S-Tier SaaS design checklist (colors, typography, spacing, components, accessibility)
- **`docs/searchable-system-reference.md`** - Complete reference for the searchable DSL system

Testing standards are in the `system-test-writer` skill (`.claude/skills/system-test-writer/`).

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
- **Squared edges**: Use `rounded` not `rounded-lg/xl/2xl` for professional aesthetic

### Tailwind CSS Important Notes

- **Rebuild after adding new classes**: When using Tailwind utility classes that weren't previously in the codebase (e.g., new responsive variants like `sm:hidden`, `sm:flex`), you must rebuild:
  ```bash
  bin/rails tailwindcss:build
  ```
- If `bin/dev` is running, it watches for changes automatically
- If styles aren't applying, always check if the CSS needs rebuilding first

### Quick Visual Check

IMMEDIATELY after implementing any front-end change:

1. **Identify what changed** - Review the modified components/pages
2. **Navigate to affected pages** - Use the `agent-browser` skill to visit each changed view
3. **Verify design compliance** - Compare against `/docs/design-standards.md`
4. **Validate feature implementation** - Ensure the change fulfills the user's specific request
5. **Check acceptance criteria** - Review any provided context files or requirements
6. **Capture evidence** - Take full page screenshot at desktop viewport (1440px) of each changed view
7. **Check for errors** - Check browser console for JavaScript errors

This verification ensures changes meet design standards and user requirements.

### Browser Login Credentials

When accessing the website through agent-browser, use these credentials:
- **Email**: `demo@example.com`
- **Password**: `password123`

### Cleanup After Visual Verification

After completing visual verification with agent-browser, clean up any saved screenshots:
```bash
rm -f *.png
```
This prevents accumulation of temporary screenshot files in the repository.

### Comprehensive Design Review

Invoke the `design-review` agent for thorough design validation when:

- Completing significant UI/UX features
- Before finalizing PRs with visual changes
- Needing review of styling consistency and color usage

The design-review agent reads the design standards and performs:
- Verification against custom.css color tokens and component specs
- Consistency checks with project styling standards (squared edges, spacing)
- Responsive layout logic verification
- Visual hierarchy and typography assessment
- Anti-pattern detection per the design standards guide

---

## Testing Workflow

Use the `system-test-writer` skill to write system tests. This skill handles page-based test organization, DRY patterns, and all project testing conventions automatically.

### Running Tests

Always run test files one at a time, never entire directories or the full suite:

```bash
bundle exec rspec spec/system/feature_name/page/section_spec.rb  # Run one file at a time
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
7. **Write tests** - Use the `system-test-writer` skill
8. **Run tests** - Run each test file individually with `bundle exec rspec path/to/spec.rb`
9. **Commit** - Only after all checks pass
