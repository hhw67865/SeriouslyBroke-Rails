# frozen_string_literal: true

module Searchable
  extend ActiveSupport::Concern

  private

  # Apply search to a query using the model's searchable configuration
  # @param query [ActiveRecord::Relation] The base query to search
  # @param search_params [Hash] Hash containing 'q' (search term) and 'field' (search field)
  # @return [ActiveRecord::Relation] The filtered query
  def apply_search(query, search_params = {})
    search_term = search_params[:q]&.strip
    search_field = search_params[:field]

    return query if search_term.blank? || search_field.blank?

    # Use the model's search_by method if available
    if query.model.respond_to?(:search_by)
      query.search_by(search_field, search_term)
    else
      query
    end
  end

  # Get search field options for dropdowns from the model
  # @return [Array<Array>] Array of [display_name, field_key] pairs
  def search_field_options
    model_class = controller_model_class
    return [] unless model_class.respond_to?(:searchable_options)

    model_class.searchable_options
  end

  # Get current search state
  # @param params [ActionController::Parameters] Controller params
  # @return [Hash] Current search parameters
  def current_search_state(params)
    {
      query: params[:q],
      field: params[:field],
      has_search: params[:q].present? && params[:field].present?
    }
  end

  # Determine the model class for this controller
  # Override this method in controllers if the convention doesn't work
  def controller_model_class
    @controller_model_class ||= begin
      controller_name.classify.constantize
    rescue NameError
      nil
    end
  end
end
