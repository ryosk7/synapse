# frozen_string_literal: true

module Flehmen
  module Presentation
    # Applies PII masking to a record attribute hash based on field classifications and the current role.
    #
    # Masking rules:
    #   public / internal  → always shown as-is
    #   personal           → shown to :admin; partial mask for others
    #   sensitive          → always [FILTERED] regardless of role
    #   restricted         → excluded from output entirely for non-admin roles
    #
    # Default (no classification declared) → treated as :personal (safe side).
    class Masker
      FILTERED  = "[FILTERED]"
      REDACTED  = "[REDACTED]"

      MASK_FUNCTIONS = {
        email:   ->(v) { v.to_s.sub(/\A(.).+(@.+)\z/, '\1***\2') },
        phone:   ->(v) { v.to_s.gsub(/.(?=.{4})/, "*") },
        name:    ->(v) { v.to_s.empty? ? v : "#{v.to_s[0]}#{"*" * [v.to_s.length - 1, 1].max}" },
        full:    ->(_) { FILTERED },
        exclude: nil  # handled via exclusion, not value replacement
      }.freeze

      # @param attributes   [Hash]               record.attributes or subset
      # @param field_defs   [Hash<Symbol, FieldDefinition>]  from ResourceDefinition#fields
      # @param role         [String, Symbol, nil]
      # @return [Hash] masked attributes (excluded fields are omitted)
      def mask(attributes, field_defs, role)
        role = role&.to_sym

        attributes.each_with_object({}) do |(raw_key, value), result|
          key      = raw_key.to_sym
          field    = field_defs[key]

          # Unknown fields (not declared in catalog) are treated as personal
          if field.nil?
            result[raw_key] = role == :admin ? value : FILTERED
            next
          end

          # Excluded fields are omitted
          next if field.excluded_for_role?(role)

          if field.masked_for_role?(role)
            result[raw_key] = apply_mask(value, field.mask_strategy)
          else
            result[raw_key] = value
          end
        end
      end

      # Produce a redacted version of a value for audit logs.
      # Never writes the actual sensitive value to logs.
      def redact(value, field_def)
        return value if field_def.nil?
        return REDACTED if %i[personal sensitive restricted].include?(field_def.classification)

        value
      end

      private

      def apply_mask(value, strategy)
        return FILTERED if strategy.nil? || !MASK_FUNCTIONS.key?(strategy)
        return FILTERED if strategy == :exclude

        fn = MASK_FUNCTIONS[strategy]
        return FILTERED if fn.nil?
        return FILTERED if value.nil?

        fn.call(value)
      rescue StandardError
        FILTERED
      end
    end
  end
end
