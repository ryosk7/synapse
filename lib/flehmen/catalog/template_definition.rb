# frozen_string_literal: true

module Flehmen
  module Catalog
    # Declares a named, reusable query template.
    #
    # A template defines:
    #   - which resource (model) to query
    #   - which fields to include in the output
    #   - what parameters Claude must supply
    #   - what filters to apply (including static ones)
    #   - default ordering
    #
    # Example:
    #
    #   c.template :recent_tickets do |t|
    #     t.description "顧客の直近の問い合わせ一覧"
    #     t.resource :Ticket
    #     t.fields [:id, :subject, :status, :priority, :created_at]
    #     t.param :customer_id, type: :integer, required: true
    #     t.param :days_ago, type: :integer, required: false, default: 30
    #     t.filter :by_customer, field: :customer_id, operator: :eq, param: :customer_id
    #     t.filter :recent, field: :created_at, operator: :gte, param: :days_ago,
    #              transform: ->(days) { days.days.ago }
    #     t.default_order :created_at, :desc
    #   end
    class TemplateDefinition
      attr_reader :name, :resource_name, :field_names, :params,
                  :filters, :default_order_field, :default_order_dir

      def initialize(name)
        @name               = name.to_sym
        @resource_name      = nil
        @field_names        = []
        @params             = {}
        @filters            = {}
        @default_order_field = nil
        @default_order_dir  = :asc
        @description_text   = nil
      end

      # DSL -------------------------------------------------------------------

      def description(text = nil)
        return @description_text if text.nil?

        @description_text = text
      end

      def resource(name)
        @resource_name = name.to_sym
      end

      def fields(list)
        @field_names = list.map(&:to_sym)
      end

      def param(name, type:, required: true, default: nil, description: nil)
        @params[name.to_sym] = ParamDefinition.new(
          name,
          type: type,
          required: required,
          default: default,
          description: description
        )
      end

      def filter(name, field:, operator:, param: nil, value: nil, transform: nil)
        @filters[name.to_sym] = FilterDefinition.new(
          name,
          field: field.to_s,
          operator: operator.to_s,
          param: param,
          value: value,
          transform: transform
        )
      end

      def default_order(field, dir = :asc)
        @default_order_field = field.to_s
        @default_order_dir   = dir.to_sym
      end

      # Helpers ---------------------------------------------------------------

      def required_params
        @params.values.select(&:required)
      end

      def optional_params
        @params.values.select(&:optional?)
      end

      def param_driven_filters
        @filters.values.reject(&:static?)
      end

      def static_filters
        @filters.values.select(&:static?)
      end

      # Build schema hash for Claude's reference (via CatalogResource / CatalogTool).
      def to_schema_hash
        {
          name: @name.to_s,
          description: @description_text,
          resource: @resource_name&.to_s,
          params: @params.transform_values(&:to_schema_hash),
          fields: @field_names.map(&:to_s)
        }
      end
    end
  end
end
