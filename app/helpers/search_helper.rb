# frozen_string_literal: true

module SearchHelper
  # Generate placeholder text based on the selected search field
  def search_placeholder(field)
    search_placeholders.fetch(field&.to_s, "Enter search term...")
  end

  # Get search field options for the current controller
  def search_field_options_for_controller
    if controller.respond_to?(:search_field_options, true)
      controller.send(:search_field_options)
    else
      []
    end
  end

  # Check if current controller supports search functionality
  def controller_supports_search?
    controller.class.included_modules.include?(Searchable) &&
      search_field_options_for_controller.any?
  end

  # Generate search results count text
  def search_results_text(collection, search_state)
    return "" unless search_state[:has_search]

    count = collection_total_count(collection)
    field_name = find_field_label(search_state[:field])

    "Found #{pluralize(count, "result")} for \"#{search_state[:query]}\" in #{field_name}"
  end

  # Helper to determine if we should show search form
  def show_search_form?
    controller_supports_search?
  end

  # Get search options with current selection for dropdowns
  # Used in search form partials
  def search_options_with_selection(current_field = nil)
    options_for_select(search_field_options_for_controller, current_field)
  end

  # Build search state hash from params for views
  # Provides consistent interface for search form state
  def build_search_state(params)
    {
      query: params[:q],
      field: params[:field],
      has_search: params[:q].present? && params[:field].present?
    }
  end

  # Generate CSS classes for search form elements based on state
  def search_form_css_classes(has_results: false, is_active: false)
    base_classes = "bg-white rounded-lg shadow-sm border"

    if has_results
      "#{base_classes} border-brand"
    elsif is_active
      "#{base_classes} border-gray-300 ring-2 ring-brand ring-opacity-50"
    else
      "#{base_classes} border-gray-200"
    end
  end

  # Get entry type configuration for headers
  def entry_type_config(type)
    configs = {
      "all" => {
        title: "All Entries",
        description: "Manage all your financial transactions in one place"
      },
      "expenses" => {
        title: "Expenses",
        description: "Track and manage your expense transactions"
      },
      "income" => {
        title: "Income",
        description: "Monitor your income sources and earnings"
      },
      "savings" => {
        title: "Savings",
        description: "Record your savings deposits and contributions"
      }
    }

    configs[type&.to_s] || configs["all"]
  end

  # Get JavaScript placeholders object for search fields
  def search_placeholders_js
    # Return JSON string - escaping handled by view context
    search_placeholders.to_json
  end

  private

  def collection_total_count(collection)
    # Use total_count for paginated collections (Kaminari), otherwise use count
    if collection.respond_to?(:total_count)
      collection.total_count
    elsif collection.respond_to?(:size)
      collection.size
    else
      collection.count
    end
  end

  def find_field_label(field)
    search_field_options_for_controller
      .find { |opt| opt[1].to_s == field.to_s }&.first || field
  end

  def search_placeholders
    {
      "date" => "e.g., 2024-01-15, 2024-3, 2025-9, or 2024",
      "item" => "e.g., Coffee, Rent, Salary",
      "description" => "e.g., Monthly payment, Grocery shopping",
      "category" => "e.g., Food, Housing, Income",
      "name" => "e.g., Coffee, Food, Emergency Fund",
      "category_type" => "e.g., expense, income, savings",
      "target_amount" => "e.g., 1000, 5000"
    }
  end
end
