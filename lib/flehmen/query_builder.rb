# frozen_string_literal: true

module Flehmen
  class QueryBuilder
    ALLOWED_OPERATORS = %w[eq not_eq gt gte lt lte like not_like in not_in null not_null].freeze

    def initialize(model_info, config = Flehmen.configuration)
      @klass = model_info[:klass]
      @column_names = model_info[:columns].map { |c| c[:name] }
      @config = config
    end

    def build(conditions: [], order_by: nil, order_dir: "asc", limit: nil, offset: nil)
      scope = @klass.all

      conditions.each do |cond|
        scope = apply_condition(scope, cond)
      end

      scope = apply_ordering(scope, order_by, order_dir)
      scope = scope.limit(effective_limit(limit))
      scope = scope.offset(offset.to_i) if offset && offset.to_i > 0
      scope
    end

    private

    def apply_condition(scope, cond)
      field    = cond["field"]&.to_s || cond[:field]&.to_s
      operator = cond["operator"]&.to_s || cond[:operator]&.to_s
      value    = cond["value"] || cond[:value]

      raise ArgumentError, "Missing field in condition" if field.nil? || field.empty?
      raise ArgumentError, "Missing operator in condition" if operator.nil? || operator.empty?
      raise ArgumentError, "Unknown column: #{field}" unless @column_names.include?(field)
      raise ArgumentError, "Unknown operator: #{operator}" unless ALLOWED_OPERATORS.include?(operator)

      table = @klass.arel_table

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
      end
    end

    def apply_ordering(scope, order_by, order_dir)
      return scope.order(id: :asc) unless order_by

      raise ArgumentError, "Unknown column: #{order_by}" unless @column_names.include?(order_by.to_s)

      dir = %w[asc desc].include?(order_dir.to_s.downcase) ? order_dir.to_s.downcase.to_sym : :asc
      scope.order(order_by.to_sym => dir)
    end

    def effective_limit(requested)
      max = @config.max_results
      return max unless requested

      [requested.to_i, max].min
    end

    def sanitize_like(value)
      # Escape special LIKE characters to prevent unintended wildcards
      value.to_s.gsub("\\", "\\\\\\\\").gsub("%", "\\%").gsub("_", "\\_")
    end
  end
end
