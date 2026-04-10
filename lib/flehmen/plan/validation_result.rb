# frozen_string_literal: true

module Flehmen
  module Plan
    # Immutable result object returned by Validator#validate.
    #
    # status:
    #   :valid     — plan is accepted as-is
    #   :corrected — plan was auto-corrected (e.g. limit clamped); corrected_plan contains the final plan
    #   :rejected  — plan cannot be executed; errors contains reasons
    class ValidationResult
      attr_reader :status, :errors, :warnings, :corrected_plan

      def initialize(status:, errors: [], warnings: [], corrected_plan: nil)
        @status         = status
        @errors         = Array(errors).freeze
        @warnings       = Array(warnings).freeze
        @corrected_plan = corrected_plan&.freeze
      end

      def valid?
        @status == :valid
      end

      def corrected?
        @status == :corrected
      end

      def rejected?
        @status == :rejected
      end

      # The plan to actually execute: corrected version if available, else nil (caller uses original).
      def effective_plan
        @corrected_plan
      end

      def self.valid(warnings: [])
        new(status: :valid, warnings: warnings)
      end

      def self.corrected(plan, warnings: [])
        new(status: :corrected, corrected_plan: plan, warnings: warnings)
      end

      def self.rejected(errors, warnings: [])
        new(status: :rejected, errors: errors, warnings: warnings)
      end
    end
  end
end
