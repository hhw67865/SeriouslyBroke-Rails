# frozen_string_literal: true

module ModelSearchable
  extend ActiveSupport::Concern

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

    # Perform search on the model
    def search_by(field, query)
      return all if query.blank? || field.blank?
      
      field_config = searchable_field_config(field.to_sym)
      return all unless field_config

      case field_config[:type]
      when :date
        search_by_date(field_config[:column], query)
      when :association
        search_by_association(field_config, query)
      when :nested_association
        search_by_nested_association(field_config, query)
      else
        search_by_direct(field_config[:column], query)
      end
    end

    private

    def build_searchable_config(field, options)
      config = { column: field, label: field.to_s.humanize }
      
      if options[:type]
        config[:type] = options[:type]
      elsif options[:through]
        if options[:through].is_a?(Array)
          config[:type] = :nested_association
          config[:associations] = build_nested_associations(options[:through])
          config[:table] = options[:through].last.to_s.pluralize
        else
          config[:type] = :association
          config[:association] = options[:through]
          config[:table] = options[:through].to_s.pluralize
        end
        config[:column] = options[:column] if options[:column]
      else
        config[:type] = :direct
      end

      config
    end

    def build_nested_associations(through_array)
      result = {}
      current = result
      
      through_array.each_with_index do |assoc, index|
        if index == through_array.length - 1
          current[assoc] = nil
        else
          current[assoc] = {}
          current = current[assoc]
        end
      end
      
      result
    end

    def search_by_direct(column, query)
      where("#{table_name}.#{column} ILIKE ?", "%#{query}%")
    end

    def search_by_association(config, query)
      joins(config[:association])
        .where("#{config[:table]}.#{config[:column]} ILIKE ?", "%#{query}%")
    end

    def search_by_nested_association(config, query)
      joins(config[:associations])
        .where("#{config[:table]}.#{config[:column]} ILIKE ?", "%#{query}%")
    end

    def search_by_date(column, query)
      begin
        date = Date.parse(query)
        where(column => date.beginning_of_day..date.end_of_day)
      rescue Date::Error
        # If parsing fails, search for partial matches in formatted date
        where("TO_CHAR(#{table_name}.#{column}, 'YYYY-MM-DD') ILIKE ? OR TO_CHAR(#{table_name}.#{column}, 'Mon DD, YYYY') ILIKE ?", 
              "%#{query}%", "%#{query}%")
      end
    end
  end
end 