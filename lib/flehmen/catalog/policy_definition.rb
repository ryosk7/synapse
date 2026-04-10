# frozen_string_literal: true

module Flehmen
  module Catalog
    # Defines what a given role is permitted to do.
    #
    # Example:
    #
    #   c.policy :support do |p|
    #     p.allow_templates :customer_overview, :recent_tickets
    #     p.max_results 50
    #   end
    #
    #   c.policy :admin do |p|
    #     p.allow_all_templates
    #     p.max_results 100
    #   end
    class PolicyDefinition
      # Sentinel indicating unrestricted access to all templates.
      ALL_TEMPLATES = :__all__

      attr_reader :role, :max_results_limit

      def initialize(role)
        @role                  = role.to_sym
        @allowed_template_names = nil  # nil = no access until explicitly set
        @max_results_limit     = 100
      end

      # DSL -------------------------------------------------------------------

      def allow_templates(*template_names)
        @allowed_template_names = template_names.flatten.map(&:to_sym)
      end

      def allow_all_templates
        @allowed_template_names = ALL_TEMPLATES
      end

      def max_results(limit)
        @max_results_limit = limit.to_i
      end

      # Queries ---------------------------------------------------------------

      def allows_template?(template_name)
        return false if @allowed_template_names.nil?
        return true  if @allowed_template_names == ALL_TEMPLATES

        @allowed_template_names.include?(template_name.to_sym)
      end

      def unrestricted?
        @allowed_template_names == ALL_TEMPLATES
      end
    end
  end
end
