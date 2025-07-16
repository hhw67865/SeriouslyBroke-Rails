# Searchable System Reference

## Overview
This document describes the elegant searchable system implemented in the SeriouslyBroke Rails application. It provides a Rails-like DSL for configuring model search functionality with automatic controller and view integration.

## Architecture Components

### 1. ModelSearchable Concern (`app/models/concerns/model_searchable.rb`)

**Purpose**: Provides a Rails-like DSL for models to configure searchable fields.

**Key Features**:
- `searchable` class method for field configuration
- Automatic SQL generation for different field types
- Support for direct fields, associations, nested associations, and dates
- Stores configuration in `_searchable_fields` class attribute

**DSL Examples**:
```ruby
searchable :description, label: "Description"                    # Direct column
searchable :date, type: :date, label: "Date"                    # Date field with special parsing
searchable :item, through: :item, column: :name, label: "Item"  # Single association
searchable :category, through: [:item, :category], column: :name, label: "Category" # Nested association
```

**Generated Methods**:
- `Model.searchable_columns` - Returns array of searchable field names
- `Model.searchable_options` - Returns [label, field] pairs for dropdowns
- `Model.search_by(field, query)` - Performs the actual search

### 2. Searchable Controller Concern (`app/controllers/concerns/searchable.rb`)

**Purpose**: Provides search functionality to controllers with minimal configuration.

**Key Methods**:
- `apply_search(query, search_params)` - Applies search to ActiveRecord relation
- `search_field_options` - Gets dropdown options from model
- `current_search_state(params)` - Extracts search state from params
- `controller_model_class` - Auto-detects model from controller name

**Usage**: Just `include Searchable` in controller and call `apply_search` in query building.

### 3. View Integration - Standardized Page Header (`app/views/shared/_page_header.html.erb`)

**Modern Implementation**: Search is now integrated into the standardized page header component.

**Features**:
- **Unified Header Component**: Combines breadcrumbs, search, and action buttons
- **Flexible Search Configuration**: Supports both simple search (categories) and advanced search with field selectors (entries)  
- **Professional UX**: Integrated design with consistent styling across all sections
- **Dynamic Placeholders**: JavaScript-powered placeholder updates via Stimulus controller
- **Auto-generates dropdown**: From model configuration via `search_field_options_for_controller`
- **URL Parameter Preservation**: Maintains type, sorting, and other filters
- **Responsive Design**: Professional styling that adapts to mobile/desktop

**Usage Pattern**:
```erb
<%= render 'shared/page_header',
    title: "Page Title",
    subtitle: "Description", 
    search: {
      enabled: true,
      url: entries_path,
      field_selector: {                    # For advanced search (entries)
        options: search_options_with_selection(@search_state[:field]),
        selected: @search_state[:field],
        placeholders: search_placeholders_js
      },
      query: @search_state[:query],        # Current search query
      placeholder: search_placeholder(@search_state[:field]),
      has_results: @search_state[:has_search],
      results_text: search_results_text(@entries, @search_state),
      hidden_fields: { type: @current_type } # Preserve other params
    },
    actions: [{ label: "New Entry", url: new_entry_path }]
%>

### 4. Search Helper (`app/helpers/search_helper.rb`)

**Dedicated helper module for all search-related functionality**:

**Core Search Helpers**:
- `search_placeholder(field)` - Dynamic placeholders based on field type
- `search_field_options_for_controller` - Gets dropdown options from controller
- `controller_supports_search?` - Checks if search functionality is available
- `search_results_text(collection, search_state)` - Generates results count display
- `show_search_form?` - Determines if search form should be rendered

**Enhanced Helpers**:
- `search_options_with_selection(current_field)` - Pre-selected dropdown options
- `build_search_state(params)` - Consistent search state extraction  
- `search_form_css_classes(has_results:, is_active:)` - Dynamic CSS classes

**Helper Organization**:
- Rails automatically includes all helpers in `app/helpers/` for all views
- SearchHelper is focused solely on search functionality
- ApplicationHelper now includes standardized page header helpers (`page_header`, `standard_action_button`, `breadcrumb_trail`)
- Each helper has a single responsibility with clean separation of concerns

## Implementation Example: Entry Model

```ruby
class Entry < ApplicationRecord
  include ModelSearchable
  
  # Configure what's searchable
  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
end
```

## Controller Integration Example

```ruby
class EntriesController < ApplicationController
  include Searchable
  
  def index
    @entries = build_entries_query
    @search_state = current_search_state(params)
  end

  private

  def build_entries_query
    entries = current_user.entries.includes(item: :category)
    entries = apply_type_filter(entries)
    entries = apply_search(entries, { q: params[:q], field: params[:field] })
    entries = apply_sorting(entries)
    entries
  end
end
```

## Helper Usage Examples

### In Views - Modern Standardized Header Pattern
```erb
<!-- Simple Search (Categories Style) -->
<%= render 'shared/page_header',
    title: "#{@type.titleize} Categories",
    subtitle: "Manage your categories and track progress",
    search: {
      enabled: true,
      url: categories_path,
      query: @query,
      placeholder: "Search #{@type} categories...",
      has_results: @query.present?,
      hidden_fields: { type: @type }
    },
    actions: [{ label: "New Category", url: new_category_path }]
%>

<!-- Advanced Search with Field Selector (Entries Style) -->
<% type_config = entry_type_config(@current_type) %>
<%= render 'shared/page_header',
    title: type_config[:title],
    subtitle: type_config[:description],
    search: show_search_form? ? {
      enabled: true,
      url: entries_path,
      field_selector: {
        options: search_options_with_selection(@search_state[:field]),
        selected: @search_state[:field],
        placeholders: search_placeholders_js
      },
      query: @search_state[:query],
      placeholder: search_placeholder(@search_state[:field]),
      has_results: @search_state[:has_search],
      results_text: search_results_text(@entries, @search_state),
      hidden_fields: { type: (@current_type != 'all' ? @current_type : nil) }
    } : nil,
    actions: [{ label: "New Entry", url: new_entry_path }]
%>
```

### Using Helper Methods for Cleaner Code
```erb
<!-- Using the page_header helper for even cleaner syntax -->
<%= page_header(
      title: "Dashboard",
      search: search_enabled? ? search_config : nil,
      actions: [standard_action_button(label: "Export", url: export_path, style: :secondary)]
    ) %>

<!-- Helper methods in action -->
<%= standard_action_button(label: "New Item", url: new_item_path, style: :primary) %>
<%= breadcrumb_trail([{label: "Home", url: root_path}, {label: "Current"}]) %>
```

## Search Flow

1. **User selects field and enters query** → Form submits to `?field=item&q=coffee`
2. **Controller processes** → `apply_search(entries, {q: "coffee", field: "item"})`
3. **Delegation to model** → `Entry.search_by("item", "coffee")`
4. **Configuration lookup** → Finds item config: `{type: :association, association: :item, column: :name}`
5. **SQL generation** → `entries.joins(:item).where("items.name ILIKE ?", "%coffee%")`
6. **Results returned** → All entries where item name contains "coffee"

## Search Types Supported

### Direct Column Search
```ruby
searchable :description
# Generates: WHERE entries.description ILIKE '%query%'
```

### Association Search
```ruby
searchable :item, through: :item, column: :name
# Generates: JOIN items ON ... WHERE items.name ILIKE '%query%'
```

### Nested Association Search
```ruby
searchable :category, through: [:item, :category], column: :name
# Generates: JOIN items ON ... JOIN categories ON ... WHERE categories.name ILIKE '%query%'
```

### Date Search
```ruby
searchable :date, type: :date
# Handles: Date parsing, range queries, partial date matching
```

## Extension Points

### Adding New Field Types
Extend `search_by` method in `ModelSearchable`:
```ruby
when :custom_type
  search_by_custom(field_config, query)
```

### Adding to New Models
1. `include ModelSearchable`
2. Configure with `searchable` DSL
3. Done! Controller integration works automatically.

### Adding to New Controllers
1. `include Searchable`
2. Call `apply_search` in query building
3. Use `current_search_state` for view state
4. Include search form partial in view

## Files Modified/Created

### Core System Files
- `app/models/concerns/model_searchable.rb` - Model DSL and search engine
- `app/controllers/concerns/searchable.rb` - Controller integration
- `app/views/shared/_page_header.html.erb` - **NEW**: Standardized page header with integrated search
- `app/helpers/search_helper.rb` - Dedicated search helper methods
- `app/helpers/application_helper.rb` - **UPDATED**: Added standardized page header helpers
- `app/javascript/controllers/shared/search_placeholder_controller.js` - **NEW**: Stimulus controller for dynamic placeholders

### Implementation Files
- `app/models/entry.rb` - Example model configuration
- `app/controllers/entries_controller.rb` - Example controller usage
- `app/views/entries/index.html.erb` - **UPDATED**: Uses standardized page header
- `app/views/categories/index.html.erb` - **UPDATED**: Uses standardized page header
- `app/views/entries/_table.html.erb` - **RENAMED**: From `_entries_table.html.erb`, now uses collection render
- `app/views/entries/_entry.html.erb` - **NEW**: Individual entry row partial

### Removed Files (Replaced by Standardized Component)
- `app/views/entries/_header.html.erb` - **DELETED**: Replaced by standardized page header
- `app/views/categories/_partials/_header.html.erb` - **DELETED**: Replaced by standardized page header

## Key Benefits

1. **Rails-like DSL**: Feels natural and follows Rails conventions
2. **Separation of Concerns**: Model defines searchable fields, controller just applies search
3. **Automatic Integration**: Views automatically adapt to model configuration
4. **Type Safety**: Different field types generate appropriate SQL
5. **Extensible**: Easy to add new models, controllers, and field types
6. **Reusable**: Same form component works across different models
7. **Organized Helpers**: Dedicated SearchHelper keeps search functionality grouped and ApplicationHelper clean

## Performance Considerations

- Uses proper JOIN syntax for associations
- Includes eager loading hints in controller (`includes(item: :category)`)
- ILIKE queries are case-insensitive but may need indexing for large datasets
- Date searches handle both exact dates and partial matches efficiently

## Future Enhancement Ideas

- Add search result highlighting
- Support for advanced operators (exact match, greater than, etc.)
- Multi-field search
- Search history/saved searches
- Full-text search integration (pg_search)
- Search analytics/logging

## Class Method Pattern Understanding

This system demonstrates how Rails uses **class methods** executed during class definition:

```ruby
class Entry < ApplicationRecord
  include ModelSearchable          # Module inclusion
  
  belongs_to :item                 # Class method call (Rails)
  validates :amount, presence: true # Class method call (Rails)
  scope :expenses, -> { ... }      # Class method call (Rails)
  
  searchable :description          # Class method call (Our custom DSL)
end
```

All of these (`belongs_to`, `validates`, `scope`, `searchable`) are **class methods** that:
- Execute immediately when the class is loaded
- Configure the class behavior
- Store metadata for runtime use
- Follow the same metaprogramming pattern

This is the essence of Ruby's power - code that writes code during class definition! 