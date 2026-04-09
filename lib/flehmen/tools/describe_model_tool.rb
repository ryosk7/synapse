# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    class DescribeModelTool < FastMcp::Tool
      tool_name "flehmen_describe_model"
      description "Show the full schema for a model: columns (name, type, null, default), associations (name, type, target class), and enum definitions"

      arguments do
        required(:model_name).filled(:string).description("Name of the model class, e.g. 'User' or 'Post'")
      end

      annotations(
        read_only_hint: true,
        open_world_hint: false
      )

      def call(model_name:)
        info = Flehmen.model_registry.find_model(model_name)
        return JSON.generate({ error: "Model not found: #{model_name}" }) unless info

        filter = Flehmen::FieldFilter.new
        result = {
          model: model_name,
          table_name: info[:table_name],
          primary_key: info[:primary_key],
          columns: filter.visible_columns(model_name, info[:columns]),
          associations: info[:associations],
          enums: info[:enums]
        }
        JSON.generate(result)
      end
    end
  end
end
