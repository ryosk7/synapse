# frozen_string_literal: true

require "json"

module Synapse
  module Tools
    class ListModelsTool < FastMcp::Tool
      tool_name "synapse_list_models"
      description "List all available ActiveRecord models with their table names, column counts, and association counts"

      annotations(
        read_only_hint: true,
        open_world_hint: false
      )

      def call(**_args)
        registry = Synapse.model_registry
        models = registry.model_names.map do |name|
          info = registry.find_model(name)
          {
            name: name,
            table_name: info[:table_name],
            column_count: info[:columns].size,
            association_count: info[:associations].size,
            enum_count: info[:enums].size
          }
        end
        JSON.generate(models)
      end
    end
  end
end
