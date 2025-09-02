# frozen_string_literal: true

module ModelSearchable
  module ConfigBuilder
    extend ActiveSupport::Concern

    class_methods do
      private

      def build_searchable_config(field, options)
        config = initialize_base_config(field)
        apply_field_type(config, options)
        config
      end

      def initialize_base_config(field)
        { column: field, label: field.to_s.humanize }
      end

      def apply_field_type(config, options)
        if options[:type]
          config[:type] = options[:type]
        elsif options[:through]
          ConfigBuilder.configure_association_type(config, options)
        else
          config[:type] = :direct
        end
      end
    end

    module_function

    def configure_association_type(config, options)
      if options[:through].is_a?(Array)
        ConfigBuilder.configure_nested_association(config, options)
      else
        ConfigBuilder.configure_simple_association(config, options)
      end
      config[:column] = options[:column] if options[:column]
    end

    def configure_nested_association(config, options)
      config[:type] = :nested_association
      config[:associations] = ConfigBuilder.build_nested_associations(options[:through])
      config[:table] = options[:through].last.to_s.pluralize
    end

    def configure_simple_association(config, options)
      config[:type] = :association
      config[:association] = options[:through]
      config[:table] = options[:through].to_s.pluralize
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
  end
end
