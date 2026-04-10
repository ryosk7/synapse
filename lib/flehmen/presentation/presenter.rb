# frozen_string_literal: true

module Flehmen
  module Presentation
    # Serializes ActiveRecord records according to a template's declared field list,
    # then applies PII masking via Masker.
    #
    # Only fields declared in template.field_names are included in the output.
    # This ensures fields not listed in the template never leak, even if the DB returns them.
    class Presenter
      def initialize(registry, role:, masker: Masker.new)
        @registry = registry
        @role     = role&.to_s
        @masker   = masker
      end

      # @param records  [Array<ActiveRecord::Base>]
      # @param template [Catalog::TemplateDefinition]
      # @return [Array<Hash>]
      def present(records, template)
        resource   = @registry.find_resource(template.resource_name)
        field_defs = resource&.fields || {}
        field_keys = template.field_names.map(&:to_s)

        records.map { |record| serialize_record(record, field_keys, field_defs) }
      end

      # Returns a list of field names that will be masked for the current role,
      # useful for surfacing warnings to Claude.
      def masked_field_names(template)
        resource = @registry.find_resource(template.resource_name)
        return [] unless resource

        template.field_names.select do |field_name|
          fd = resource.field_definition(field_name)
          fd&.masked_for_role?(@role)
        end.map(&:to_s)
      end

      private

      def serialize_record(record, field_keys, field_defs)
        # Build the attribute subset: only declared template fields
        subset = field_keys.each_with_object({}) do |key, h|
          h[key] = record.attributes[key]
        end

        # Symbolize for Masker
        sym_defs = field_defs.transform_keys(&:to_sym)
        masked   = @masker.mask(subset, sym_defs, @role)

        # Return with string keys for JSON serialization
        masked.transform_keys(&:to_s)
      end
    end
  end
end
