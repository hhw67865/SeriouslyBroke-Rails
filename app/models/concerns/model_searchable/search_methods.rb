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
      # Try exact date parsing first
      exact_date = parse_exact_date(query)
      return scope.where(column => exact_date.all_day) if exact_date

      # Try month/year patterns
      date_range = parse_date_range(query)
      return scope.where(column => date_range) if date_range

      # Fall back to partial string matching
      search_by_date_string(scope, column, query)
    end

    def parse_exact_date(query)
      Date.parse(query)
    rescue Date::Error
      nil
    end

    def parse_date_range(query)
      case query.strip
      when /^\d{4}-\d{1,2}$/ # YYYY-MM or YYYY-M format
        parse_year_month_range(query)
      when /^\d{4}$/ # YYYY format
        parse_year_range(query)
      end
    end

    def parse_year_month_range(query)
      year, month = query.split("-").map(&:to_i)
      return unless (1..12).cover?(month) && year > 1900

      start_date = Date.new(year, month, 1)
      end_date = start_date.end_of_month
      start_date.beginning_of_day..end_date.end_of_day
    end

    def parse_year_range(query)
      year = query.to_i
      return unless year > 1900

      start_date = Date.new(year, 1, 1)
      end_date = Date.new(year, 12, 31)
      start_date.beginning_of_day..end_date.end_of_day
    end

    def search_by_date_string(scope, column, query)
      table = scope.table_name
      scope.where(
        "TO_CHAR(#{table}.#{column}, 'YYYY-MM-DD') ILIKE ? OR " \
        "TO_CHAR(#{table}.#{column}, 'Mon DD, YYYY') ILIKE ? OR " \
        "TO_CHAR(#{table}.#{column}, 'YYYY-MM') ILIKE ? OR " \
        "TO_CHAR(#{table}.#{column}, 'YYYY') ILIKE ?",
        "%#{query}%",
        "%#{query}%",
        "%#{query}%",
        "%#{query}%"
      )
    end
  end
end
