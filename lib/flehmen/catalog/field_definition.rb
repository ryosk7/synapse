# frozen_string_literal: true

module Flehmen
  module Catalog
    class FieldDefinition
      CLASSIFICATIONS = %i[public internal personal sensitive restricted].freeze

      # Mask strategies:
      #   :email    → t***@example.com
      #   :phone    → *****1234
      #   :name     → 田****
      #   :full     → [FILTERED]
      #   :exclude  → field is omitted from output entirely
      #   nil       → no masking (pass through)
      MASK_STRATEGIES = %i[email phone name full exclude].freeze

      attr_reader :name, :classification, :mask_strategy

      def initialize(name, classification:, mask: nil)
        @name = name.to_sym
        @classification = validate_classification!(classification)
        @mask_strategy = resolve_mask_strategy(mask, @classification)
      end

      # Whether this field should be completely excluded from output.
      # :restricted fields are always excluded — even admin requires a separate process.
      def excluded_for_role?(_role = nil)
        @mask_strategy == :exclude
      end

      # Whether this field needs masking for the given role.
      # Note: :restricted fields are excluded entirely (see excluded_for_role?), not just masked.
      def masked_for_role?(role)
        role = role&.to_sym
        case @classification
        when :public, :internal then false
        when :personal          then role != :admin
        when :sensitive         then true
        when :restricted        then false  # excluded, not masked
        end
      end

      private

      def validate_classification!(c)
        c = c.to_sym
        unless CLASSIFICATIONS.include?(c)
          raise ArgumentError, "Unknown classification: #{c}. Valid: #{CLASSIFICATIONS.join(', ')}"
        end

        c
      end

      def resolve_mask_strategy(explicit_mask, classification)
        return explicit_mask.to_sym if explicit_mask && MASK_STRATEGIES.include?(explicit_mask.to_sym)

        # Default mask strategy per classification
        case classification
        when :personal   then :full
        when :sensitive  then :full
        when :restricted then :exclude
        else nil
        end
      end
    end
  end
end
