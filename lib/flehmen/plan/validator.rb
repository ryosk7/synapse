# frozen_string_literal: true

module Flehmen
  module Plan
    # Validates a plan hash against the catalog registry and role policy.
    #
    # Usage:
    #
    #   result = Flehmen::Plan::Validator.new(registry, role: "support").validate(plan)
    #
    #   if result.rejected?
    #     # return errors to Claude
    #   else
    #     effective = result.effective_plan || plan
    #     # compile and execute effective
    #   end
    #
    # Validation order:
    #   1. template existence
    #   2. policy (role allowed to use template)
    #   3. required params presence
    #   4. params type coercion
    #   5. limit guard (auto-corrected, not rejected)
    #   6. PII access warning (informational, not rejected)
    class Validator
      def initialize(registry, role: nil)
        @registry = registry
        @role     = role&.to_s
      end

      # @param plan [Hash] with keys :template (String), :params (Hash), :options (Hash, optional)
      # @return [ValidationResult]
      def validate(plan)
        errors   = []
        warnings = []
        plan     = normalize(plan)

        # 1. Template existence
        template = @registry.find_template(plan[:template])
        unless template
          available = @registry.template_names.map(&:to_s).sort.join(", ")
          return ValidationResult.rejected(
            ["テンプレート '#{plan[:template]}' は存在しません。利用可能: #{available}"]
          )
        end

        # 2. Policy check
        if @role
          policy = @registry.find_policy(@role)
          if policy.nil? || !policy.allows_template?(template.name)
            return ValidationResult.rejected(
              ["ロール '#{@role}' はテンプレート '#{template.name}' を利用できません"]
            )
          end
        end

        # 3 & 4. Param validation and coercion
        coerced_params, param_errors = coerce_params(template, plan[:params])
        errors.concat(param_errors)
        return ValidationResult.rejected(errors) if errors.any?

        # 5. Limit guard (auto-correct, not reject)
        corrected_options, limit_warning = guard_limit(plan[:options], @role)
        warnings << limit_warning if limit_warning

        # 6. PII access warning
        resource = @registry.find_resource(template.resource_name)
        if resource
          masked_fields = pii_masked_fields(template, resource, @role)
          unless masked_fields.empty?
            warnings << "以下のフィールドは #{@role || 'このロール'} ではマスクされます: #{masked_fields.join(', ')}"
          end
        end

        # Build corrected plan if anything changed
        corrected = build_corrected_plan(plan, coerced_params, corrected_options)

        if corrected
          ValidationResult.corrected(corrected, warnings: warnings)
        else
          ValidationResult.valid(warnings: warnings)
        end
      end

      private

      def normalize(plan)
        {
          template: plan[:template]&.to_s || plan["template"]&.to_s,
          params:   symbolize_keys(plan[:params] || plan["params"] || {}),
          options:  symbolize_keys(plan[:options] || plan["options"] || {})
        }
      end

      def symbolize_keys(hash)
        hash.transform_keys(&:to_sym)
      end

      def coerce_params(template, raw_params)
        coerced = {}
        errors  = []

        template.params.each do |param_name, param_def|
          raw = raw_params[param_name]
          begin
            coerced[param_name] = param_def.coerce(raw)
          rescue ArgumentError => e
            errors << e.message
          end
        end

        # Warn about unexpected params (not fatal, just silently ignore)
        [coerced, errors]
      end

      def guard_limit(options, role)
        max = max_results_for_role(role)
        requested = options[:limit]

        return [options, nil] unless requested && requested.to_i > max

        corrected = options.merge(limit: max)
        warning   = "limit が上限 #{max} に調整されました（指定値: #{requested}）"
        [corrected, warning]
      end

      def max_results_for_role(role)
        return Flehmen.configuration.max_results unless role

        policy = @registry.find_policy(role)
        policy&.max_results_limit || Flehmen.configuration.max_results
      end

      def pii_masked_fields(template, resource, role)
        return [] unless role

        template.field_names.select do |field_name|
          field_def = resource.field_definition(field_name)
          field_def&.masked_for_role?(role)
        end.map(&:to_s)
      end

      def build_corrected_plan(original, coerced_params, corrected_options)
        params_changed  = coerced_params != original[:params]
        options_changed = corrected_options != original[:options]
        return nil unless params_changed || options_changed

        {
          template: original[:template],
          params:   params_changed  ? coerced_params    : original[:params],
          options:  options_changed ? corrected_options : original[:options]
        }
      end
    end
  end
end
