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

### 3. View Integration (`app/views/shared/_search_form.html.erb`)

**Features**:
- Auto-generates dropdown from model configuration
- Dynamic placeholders based on field type
- Preserves other URL parameters (type, sorting)
- Auto-submit on field change
- Clear search functionality

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
- ApplicationHelper remains clean with only general UI helpers (flash messages, icons)
- Each helper has a single responsibility

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

### In Views
```erb
<!-- Check if search should be shown -->
<% if show_search_form? %>
  <%= render 'shared/search_form', 
      search_options: search_field_options_for_controller,
      current_search: @search_state %>
<% end %>

<!-- Show search results count -->
<% if @search_state[:has_search] %>
  <p><%= search_results_text(@entries, @search_state) %></p>
<% end %>

<!-- Dynamic placeholder in forms -->
<%= f.text_field :q, placeholder: search_placeholder(@search_state[:field]) %>
```

### In Search Form Partial
```erb
<!-- Pre-selected dropdown options -->
<%= f.select :field, search_options_with_selection(current_search[:field]) %>

<!-- Dynamic form styling -->
<div class="<%= search_form_css_classes(has_results: @entries.any?) %>">
  <!-- form content -->
</div>
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
- `app/views/shared/_search_form.html.erb` - Reusable search form
- `app/helpers/search_helper.rb` - Dedicated search helper methods

### Implementation Files
- `app/models/entry.rb` - Example model configuration
- `app/controllers/entries_controller.rb` - Example controller usage
- `app/views/entries/index.html.erb` - View integration
- `app/views/entries/_entries_table.html.erb` - Table with search

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