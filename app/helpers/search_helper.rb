# frozen_string_literal: true

module SearchHelper
  # Generate placeholder text based on the selected search field
  def search_placeholder(field)
    case field&.to_s
    when 'date'
      'e.g., 2024-01-15 or Jan 15'
    when 'item'
      'e.g., Coffee, Rent, Salary'
    when 'description'
      'e.g., Monthly payment, Grocery shopping'
    when 'category'
      'e.g., Food, Housing, Income'
    when 'name'
      'e.g., Coffee, Food, Emergency Fund'
    when 'category_type'
      'e.g., expense, income, savings'
    when 'target_amount'
      'e.g., 1000, 5000'
    else
      'Enter search term...'
    end
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
    return '' unless search_state[:has_search]
    
    count = collection.respond_to?(:size) ? collection.size : collection.count
    field_name = search_field_options_for_controller.find { |opt| opt[1].to_s == search_state[:field].to_s }&.first || search_state[:field]
    
    "Found #{pluralize(count, 'result')} for \"#{search_state[:query]}\" in #{field_name}"
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
      'all' => {
        title: 'All Entries',
        description: 'Manage all your financial transactions in one place'
      },
      'expenses' => {
        title: 'Expenses',
        description: 'Track and manage your expense transactions'
      },
      'income' => {
        title: 'Income',
        description: 'Monitor your income sources and earnings'
      },
      'savings' => {
        title: 'Savings',
        description: 'Record your savings deposits and contributions'
      }
    }
    
    configs[type&.to_s] || configs['all']
  end

  # Get JavaScript placeholders object for search fields
  def search_placeholders_js
    {
      'date' => search_placeholder('date'),
      'item' => search_placeholder('item'),
      'description' => search_placeholder('description'),
      'category' => search_placeholder('category'),
      'name' => search_placeholder('name'),
      'category_type' => search_placeholder('category_type'),
      'target_amount' => search_placeholder('target_amount')
    }.to_json.html_safe
  end
end 