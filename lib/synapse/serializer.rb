# frozen_string_literal: true

module Synapse
  class Serializer
    def initialize(field_filter = FieldFilter.new)
      @field_filter = field_filter
    end

    def serialize_record(record)
      model_name = record.class.name
      @field_filter.filter_attributes(model_name, record.attributes)
    end

    def serialize_records(records)
      records.map { |r| serialize_record(r) }
    end
  end
end
