# frozen_string_literal: true

require "json"

module Synapse
  module Tools
    class SearchRecordsTool < FastMcp::Tool
      tool_name "synapse_search_records"
      description 'Search records with filter conditions. Each condition has a field, operator (eq, not_eq, gt, gte, lt, lte, like, in, null, not_null), and value. Example conditions: [{"field":"status","operator":"eq","value":"active"}]'

      arguments do
        required(:model_name).filled(:string).description("Name of the model class")
        optional(:conditions).filled(:string).description('JSON array of conditions: [{"field":"...", "operator":"...", "value":"..."}]')
        optional(:order_by).filled(:string).description("Column name to order by")
        optional(:order_dir).filled(:string).description("Order direction: 'asc' or 'desc'")
        optional(:limit).filled(:integer).description("Max records to return (capped by server config)")
        optional(:offset).filled(:integer).description("Number of records to skip for pagination")
      end

      annotations(
        read_only_hint: true,
        open_world_hint: false
      )

      def call(model_name:, conditions: nil, order_by: nil, order_dir: "asc", limit: nil, offset: nil)
        info = Synapse.model_registry.find_model(model_name)
        return JSON.generate({ error: "Model not found: #{model_name}" }) unless info

        parsed_conditions = conditions ? JSON.parse(conditions) : []

        builder = Synapse::QueryBuilder.new(info)
        records = builder.build(
          conditions: parsed_conditions,
          order_by: order_by,
          order_dir: order_dir,
          limit: limit,
          offset: offset
        )

        serializer = Synapse::Serializer.new
        result = {
          model: model_name,
          count: records.size,
          records: serializer.serialize_records(records)
        }
        JSON.generate(result)
      rescue JSON::ParserError
        JSON.generate({ error: "Invalid JSON in conditions parameter" })
      rescue ArgumentError => e
        JSON.generate({ error: e.message })
      end
    end
  end
end
