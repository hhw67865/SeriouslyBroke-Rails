# frozen_string_literal: true

module ModelSearchable
  module SearchMethods
    extend ActiveSupport::Concern

    included do
      # Search methods for different field types
    end

    class_methods do
      # Perform search on the model
      def search_by(field, query)
        return all if query.blank? || field.blank?

        field_config = searchable_field_config(field.to_sym)
        return all unless field_config

        case field_config[:type]
        when :date
          search_by_date(field_config[:column], query)
        when :association
          SearchMethods.search_by_association(self, field_config, query)
        when :nested_association
          SearchMethods.search_by_nested_association(self, field_config, query)
        else
          SearchMethods.search_by_direct(self, field_config[:column], query)
        end
      end

      private

      def search_by_date(column, query)
        SearchMethods.search_by_date(self, column, query)
      end
    end

    module_function

    def search_by_direct(scope, column, query)
      scope.where("#{scope.table_name}.#{column} ILIKE ?", "%#{query}%")
    end

    def search_by_association(scope, config, query)
      scope.joins(config[:association])
        .where("#{config[:table]}.#{config[:column]} ILIKE ?", "%#{query}%")
    end

    def search_by_nested_association(scope, config, query)
      scope.joins(config[:associations])
        .where("#{config[:table]}.#{config[:column]} ILIKE ?", "%#{query}%")
    end

    def search_by_date(scope, column, query)
      date = Date.parse(query)
      scope.where(column => date.all_day)
    rescue Date::Error
      # If parsing fails, search for partial matches in formatted date
      scope.where(
        "TO_CHAR(#{scope.table_name}.#{column}, 'YYYY-MM-DD') ILIKE ? OR TO_CHAR(#{scope.table_name}.#{column}, 'Mon DD, YYYY') ILIKE ?",
        "%#{query}%",
        "%#{query}%"
      )
    end
  end
end
