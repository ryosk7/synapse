# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    class ListModelsTool < Base
      tool_name "flehmen_list_models"
      description "List all available ActiveRecord models with their table names, column counts, and association counts"

      def execute(**_args)
        registry = Flehmen.model_registry
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
