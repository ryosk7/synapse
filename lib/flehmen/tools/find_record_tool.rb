# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    class FindRecordTool < FastMcp::Tool
      tool_name "flehmen_find_record"
      description "Find a single record by its primary key (usually ID)"

      arguments do
        required(:model_name).filled(:string).description("Name of the model class")
        required(:id).filled(:string).description("Primary key value of the record")
      end

      annotations(
        read_only_hint: true,
        open_world_hint: false
      )

      def call(model_name:, id:)
        info = Flehmen.model_registry.find_model(model_name)
        return JSON.generate({ error: "Model not found: #{model_name}" }) unless info

        record = info[:klass].find_by(info[:primary_key] => id)
        return JSON.generate({ error: "Record not found: #{model_name}##{id}" }) unless record

        serializer = Flehmen::Serializer.new
        JSON.generate(serializer.serialize_record(record))
      end
    end
  end
end
