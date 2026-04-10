# frozen_string_literal: true

module Flehmen
  module Catalog
    # Central registry for all catalog definitions.
    # Hosts the `Flehmen.catalog do |c| ... end` DSL.
    #
    # Usage:
    #
    #   Flehmen.catalog do |c|
    #     c.resource :Customer, model: "Customer" do |r|
    #       r.field :id,    classification: :public
    #       r.field :email, classification: :personal, mask: :email
    #     end
    #
    #     c.template :customer_overview do |t|
    #       t.description "顧客基本情報"
    #       t.resource :Customer
    #       t.fields [:id, :email]
    #       t.param :customer_id, type: :integer, required: true
    #       t.filter :by_id, field: :id, operator: :eq, param: :customer_id
    #     end
    #
    #     c.policy :support do |p|
    #       p.allow_templates :customer_overview
    #       p.max_results 50
    #     end
    #   end
    class Registry
      def initialize
        @resources = {}
        @templates = {}
        @policies  = {}
      end

      # DSL -------------------------------------------------------------------

      def resource(name, model:, &block)
        definition = ResourceDefinition.new(name, model: model)
        definition.instance_eval(&block) if block_given?
        @resources[name.to_sym] = definition
        self
      end

      def template(name, &block)
        definition = TemplateDefinition.new(name)
        definition.instance_eval(&block) if block_given?
        @templates[name.to_sym] = definition
        self
      end

      def policy(role, &block)
        definition = PolicyDefinition.new(role)
        definition.instance_eval(&block) if block_given?
        @policies[role.to_sym] = definition
        self
      end

      # Lookups ---------------------------------------------------------------

      def find_resource(name)
        @resources[name.to_sym]
      end

      def find_template(name)
        @templates[name.to_sym]
      end

      def find_policy(role)
        @policies[role.to_sym]
      end

      # Collections -----------------------------------------------------------

      def all_templates
        @templates.values
      end

      def all_resources
        @resources.values
      end

      def all_policies
        @policies.values
      end

      def template_names
        @templates.keys
      end

      def resource_names
        @resources.keys
      end

      # Returns only templates the given role is permitted to use.
      def templates_for_role(role)
        policy = find_policy(role)
        return [] unless policy

        all_templates.select { |t| policy.allows_template?(t.name) }
      end

      # Schema summary for Claude (used by CatalogResource / CatalogTool).
      def to_catalog_hash(role: nil)
        templates = role ? templates_for_role(role) : all_templates
        {
          templates: templates.map(&:to_schema_hash),
          resources: all_resources.map { |r| { name: r.name.to_s, model: r.model_name } }
        }
      end
    end
  end
end
