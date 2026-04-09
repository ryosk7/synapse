# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    class ShowAssociationsTool < FastMcp::Tool
      tool_name "flehmen_show_associations"
      description "Navigate a record's associations. Given a model, record ID, and association name, returns the associated records."

      arguments do
        required(:model_name).filled(:string).description("Name of the source model class")
        required(:id).filled(:string).description("Primary key of the source record")
        required(:association_name).filled(:string).description("Name of the association to navigate")
        optional(:limit).filled(:integer).description("Max associated records to return")
        optional(:offset).filled(:integer).description("Number of records to skip")
      end

      annotations(
        read_only_hint: true,
        open_world_hint: false
      )

      def call(model_name:, id:, association_name:, limit: nil, offset: nil)
        info = Flehmen.model_registry.find_model(model_name)
        return JSON.generate({ error: "Model not found: #{model_name}" }) unless info

        # Validate association name against declared associations
        valid_associations = info[:associations].map { |a| a[:name] }
        unless valid_associations.include?(association_name)
          return JSON.generate({ error: "Unknown association: #{association_name}" })
        end

        record = info[:klass].find_by(info[:primary_key] => id)
        return JSON.generate({ error: "Record not found: #{model_name}##{id}" }) unless record

        assoc_meta = info[:associations].find { |a| a[:name] == association_name }
        associated = record.public_send(association_name)

        serializer = Flehmen::Serializer.new
        max = Flehmen.configuration.max_results

        if %w[has_many has_and_belongs_to_many].include?(assoc_meta[:type])
          effective_limit = limit ? [limit.to_i, max].min : max
          scope = associated.limit(effective_limit)
          scope = scope.offset(offset.to_i) if offset && offset.to_i > 0
          records = scope.to_a

          JSON.generate({
            source: "#{model_name}##{id}",
            association: association_name,
            type: assoc_meta[:type],
            count: records.size,
            records: serializer.serialize_records(records)
          })
        else
          # belongs_to / has_one
          if associated
            JSON.generate({
              source: "#{model_name}##{id}",
              association: association_name,
              type: assoc_meta[:type],
              record: serializer.serialize_record(associated)
            })
          else
            JSON.generate({
              source: "#{model_name}##{id}",
              association: association_name,
              type: assoc_meta[:type],
              record: nil
            })
          end
        end
      end
    end
  end
end
