# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    class CountRecordsTool < FastMcp::Tool
      tool_name "flehmen_count_records"
      description 'Count records matching filter conditions. Example conditions: [{"field":"status","operator":"eq","value":"active"}]'

      arguments do
        required(:model_name).filled(:string).description("Name of the model class")
        optional(:conditions).filled(:string).description('JSON array of conditions: [{"field":"...", "operator":"...", "value":"..."}]')
      end

      annotations(
        read_only_hint: true,
        open_world_hint: false
      )

      def call(model_name:, conditions: nil)
        info = Flehmen.model_registry.find_model(model_name)
        return JSON.generate({ error: "Model not found: #{model_name}" }) unless info

        parsed_conditions = conditions ? JSON.parse(conditions) : []

        builder = Flehmen::QueryBuilder.new(info)
        scope = builder.build(conditions: parsed_conditions, limit: nil)
        count = scope.unscope(:limit, :offset, :order).count

        JSON.generate({ model: model_name, count: count })
      rescue JSON::ParserError
        JSON.generate({ error: "Invalid JSON in conditions parameter" })
      rescue ArgumentError => e
        JSON.generate({ error: e.message })
      end
    end
  end
end
