# frozen_string_literal: true

module Flehmen
  module Catalog
    # Represents a single predefined filter condition within a TemplateDefinition.
    #
    # A filter can be:
    #   - static: always applies the same value (e.g. status = 'failed')
    #   - param-driven: applies a value from the plan params (e.g. customer_id = :customer_id)
    #
    # The optional `transform` proc converts the raw param value before use
    # (e.g. converting days_ago: 30 → 30.days.ago as a DateTime).
    class FilterDefinition
      ALLOWED_OPERATORS = %w[eq not_eq gt gte lt lte like not_like in not_in null not_null].freeze

      attr_reader :name, :field, :operator, :param, :static_value, :transform

      def initialize(name, field:, operator:, param: nil, value: nil, transform: nil)
        @name         = name.to_sym
        @field        = field.to_s
        @operator     = operator.to_s
        @param        = param&.to_sym
        @static_value = value
        @transform    = transform
        validate!
      end

      def static?
        !@static_value.nil? && @param.nil?
      end

      # Resolve the filter value from the coerced params hash.
      # For static filters, ignores params entirely.
      def resolve_value(coerced_params)
        if static?
          @static_value
        else
          raw = coerced_params[@param]
          @transform ? @transform.call(raw) : raw
        end
      end

      private

      def validate!
        unless ALLOWED_OPERATORS.include?(@operator)
          raise ArgumentError,
                "Unknown operator '#{@operator}' in filter '#{@name}'. " \
                "Valid: #{ALLOWED_OPERATORS.join(', ')}"
        end

        if @param.nil? && @static_value.nil?
          raise ArgumentError,
                "Filter '#{@name}' must specify either :param or :value"
        end
      end
    end
  end
end
