# frozen_string_literal: true

module Flehmen
  module Catalog
    # Declares which ActiveRecord model is queryable and defines
    # the classification of each field (for PII masking).
    class ResourceDefinition
      attr_reader :name, :model_name, :fields

      def initialize(name, model:)
        @name       = name.to_sym
        @model_name = model.to_s
        @fields     = {}
      end

      # DSL: declare a field with its PII classification.
      #
      #   r.field :email, classification: :personal, mask: :email
      #   r.field :id,    classification: :public
      def field(field_name, classification:, mask: nil)
        @fields[field_name.to_sym] = FieldDefinition.new(
          field_name,
          classification: classification,
          mask: mask
        )
        self
      end

      # Retrieve the FieldDefinition for a given field name.
      def field_definition(field_name)
        @fields[field_name.to_sym]
      end

      # All declared field names as strings (used for column validation).
      def declared_column_names
        @fields.keys.map(&:to_s)
      end

      # Resolve the ActiveRecord model class. Raises if the model doesn't exist.
      def model_class
        @model_name.constantize
      rescue NameError
        raise ArgumentError, "Model '#{@model_name}' not found. Check the model: option in your catalog."
      end
    end
  end
end
