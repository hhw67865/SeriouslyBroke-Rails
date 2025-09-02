# frozen_string_literal: true

module ModelSearchable
  extend ActiveSupport::Concern

  include ModelSearchable::SearchMethods
  include ModelSearchable::ConfigBuilder

  included do
    class_attribute :_searchable_fields, default: {}
  end

  class_methods do
    # Define searchable fields using a Rails-like DSL
    # Examples:
    #   searchable :name, :description
    #   searchable :date, type: :date
    #   searchable :category, through: :category, column: :name
    #   searchable :item, through: [:item], column: :name
    def searchable(*fields, **options)
      fields.each do |field|
        field_config = build_searchable_config(field, options)
        self._searchable_fields = _searchable_fields.merge(field => field_config)
      end
    end

    # Get all searchable columns for this model
    def searchable_columns
      _searchable_fields.keys
    end

    # Get searchable field configuration
    def searchable_field_config(field)
      _searchable_fields[field.to_sym]
    end

    # Get searchable options for dropdowns [label, field_key]
    def searchable_options
      _searchable_fields.map do |field, config|
        [config[:label] || field.to_s.humanize, field]
      end
    end
  end
end
