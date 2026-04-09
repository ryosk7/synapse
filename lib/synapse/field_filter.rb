# frozen_string_literal: true

module Synapse
  class FieldFilter
    FILTERED_PLACEHOLDER = "[FILTERED]"

    def initialize(config = Synapse.configuration)
      @global_sensitive = config.sensitive_fields.map(&:to_s)
      @model_sensitive = config.model_sensitive_fields.transform_keys(&:to_s)
                                                       .transform_values { |v| v.map(&:to_s) }
    end

    def filter_attributes(model_name, attributes_hash)
      sensitive = sensitive_fields_for(model_name)
      attributes_hash.each_with_object({}) do |(k, v), filtered|
        filtered[k] = sensitive.include?(k.to_s) ? FILTERED_PLACEHOLDER : v
      end
    end

    def visible_columns(model_name, all_columns)
      sensitive = sensitive_fields_for(model_name)
      all_columns.map do |col|
        col.merge(sensitive: sensitive.include?(col[:name].to_s))
      end
    end

    private

    def sensitive_fields_for(model_name)
      @global_sensitive + (@model_sensitive[model_name.to_s] || [])
    end
  end
end
