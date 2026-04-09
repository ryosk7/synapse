# frozen_string_literal: true

require "json"

module Flehmen
  module Resources
    class SchemaOverviewResource < FastMcp::Resource
      uri "flehmen://schema/overview"
      resource_name "Database Schema Overview"
      description "Complete overview of all available models, their columns, associations, and enums"
      mime_type "application/json"

      def content
        registry = Flehmen.model_registry
        filter = Flehmen::FieldFilter.new

        overview = registry.model_names.map do |name|
          info = registry.find_model(name)
          {
            model: name,
            table: info[:table_name],
            primary_key: info[:primary_key],
            columns: filter.visible_columns(name, info[:columns]),
            associations: info[:associations],
            enums: info[:enums]
          }
        end

        JSON.pretty_generate(overview)
      end
    end
  end
end
