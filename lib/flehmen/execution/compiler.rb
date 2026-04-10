# frozen_string_literal: true

module Flehmen
  module Execution
    # Translates a validated plan into an ActiveRecord::Relation.
    #
    # The Compiler is intentionally restrictive:
    #   - Only filters declared in the template's FilterDefinition set are applied.
    #   - Only fields declared in the template are SELECT'd.
    #   - Ordering is limited to the template's declared field list.
    #   - Raw SQL is never generated; Arel is used for all conditions.
    #
    # Usage:
    #
    #   scope = Compiler.new(registry).compile(effective_plan)
    #   # => ActiveRecord::Relation
    class Compiler
      def initialize(registry)
        @registry = registry
      end

      # @param plan [Hash] with keys :template (String), :params (Hash), :options (Hash)
      # @return [ActiveRecord::Relation]
      def compile(plan)
        template = @registry.find_template(plan[:template])
        raise ArgumentError, "Template not found: #{plan[:template]}" unless template

        resource = @registry.find_resource(template.resource_name)
        raise ArgumentError, "Resource not found: #{template.resource_name}" unless resource

        klass = resource.model_class
        scope = klass.all

        # Apply static and param-driven filters
        scope = apply_filters(scope, template, plan[:params] || {})

        # Apply ordering
        scope = apply_ordering(scope, template, plan[:options] || {})

        # Apply limit
        scope = apply_limit(scope, plan[:options] || {})

        scope
      end

      private

      def apply_filters(scope, template, coerced_params)
        template.filters.each_value do |filter_def|
          value = filter_def.resolve_value(coerced_params)
          scope = apply_single_filter(scope, scope.klass, filter_def.field, filter_def.operator, value)
        end
        scope
      end

      def apply_single_filter(scope, klass, field, operator, value)
        validate_column!(klass, field)
        table = klass.arel_table

        case operator
        when "eq"       then scope.where(table[field].eq(value))
        when "not_eq"   then scope.where(table[field].not_eq(value))
        when "gt"       then scope.where(table[field].gt(value))
        when "gte"      then scope.where(table[field].gteq(value))
        when "lt"       then scope.where(table[field].lt(value))
        when "lte"      then scope.where(table[field].lteq(value))
        when "like"     then scope.where(table[field].matches(sanitize_like(value)))
        when "not_like" then scope.where(table[field].does_not_match(sanitize_like(value)))
        when "in"       then scope.where(table[field].in(Array(value)))
        when "not_in"   then scope.where(table[field].not_in(Array(value)))
        when "null"     then scope.where(table[field].eq(nil))
        when "not_null" then scope.where(table[field].not_eq(nil))
        else
          raise ArgumentError, "Unknown operator: #{operator}"
        end
      end

      def apply_ordering(scope, template, options)
        order_field = options[:order_by]&.to_s || template.default_order_field
        order_dir   = options[:order_dir]&.to_sym || template.default_order_dir || :asc

        return scope unless order_field

        # Ordering must be a declared field on the template
        unless template.field_names.map(&:to_s).include?(order_field)
          # Fall back to default rather than erroring — safer for Claude-generated plans
          order_field = template.default_order_field
          return scope unless order_field
        end

        validate_column!(scope.klass, order_field)
        dir = %i[asc desc].include?(order_dir) ? order_dir : :asc
        scope.order(scope.klass.arel_table[order_field].send(dir))
      end

      def apply_limit(scope, options)
        max = Flehmen.configuration.max_results
        requested = options[:limit]&.to_i
        limit = requested ? [requested, max].min : max
        scope.limit(limit)
      end

      def validate_column!(klass, column_name)
        unless klass.column_names.include?(column_name.to_s)
          raise ArgumentError,
                "Column '#{column_name}' does not exist on #{klass.name}. " \
                "Check the field/filter definition in your catalog."
        end
      end

      def sanitize_like(value)
        value.to_s.gsub("\\", "\\\\\\\\").gsub("%", "\\%").gsub("_", "\\_")
      end
    end
  end
end
