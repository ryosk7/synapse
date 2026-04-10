# frozen_string_literal: true

require "json"

module Flehmen
  module Audit
    # Writes structured audit log entries for every query execution.
    #
    # MVP: outputs JSON to Rails.logger (or Ruby's Logger if Rails is unavailable).
    # Future: persist to flehmen_audit_logs table.
    #
    # PII in params is redacted before logging: fields classified as personal/sensitive/restricted
    # are replaced with "[REDACTED]".
    module Logger
      LOG_TAG = "[flehmen audit]"

      class << self
        # @param template    [String]
        # @param params      [Hash]   coerced params
        # @param role        [String, nil]
        # @param user        [Object, nil] current_user (uses #id or #to_s)
        # @param record_count [Integer]
        # @param masked_fields [Array<String>]
        # @param duration_ms [Integer, nil]
        # @param registry    [Catalog::Registry, nil] used to redact PII params
        def log(template:, params:, role: nil, user: nil, record_count: 0,
                masked_fields: [], duration_ms: nil, registry: nil)
          entry = {
            flehmen: true,
            template: template,
            role: role,
            user: user_identifier(user),
            params: redact_params(template, params, registry),
            record_count: record_count,
            masked_fields: masked_fields,
            duration_ms: duration_ms,
            timestamp: iso_timestamp
          }

          log_line = "#{LOG_TAG} #{JSON.generate(entry)}"

          if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
            Rails.logger.info(log_line)
          else
            warn(log_line)
          end
        rescue StandardError => e
          # Never let audit logging crash the main flow
          warn "#{LOG_TAG} [error] Failed to write audit log: #{e.message}"
        end

        private

        def user_identifier(user)
          return nil if user.nil?
          return user.id.to_s if user.respond_to?(:id)

          user.to_s
        end

        def redact_params(template_name, params, registry)
          return params unless registry

          template = registry.find_template(template_name)
          resource = template && registry.find_resource(template.resource_name)
          return params unless resource

          params.each_with_object({}) do |(key, value), h|
            field_def = resource.field_definition(key)
            if field_def && %i[personal sensitive restricted].include?(field_def.classification)
              h[key] = "[REDACTED]"
            else
              h[key] = value
            end
          end
        end

        def iso_timestamp
          if defined?(Time) && Time.respond_to?(:current)
            Time.current.iso8601
          else
            Time.now.utc.iso8601
          end
        end
      end
    end
  end
end
