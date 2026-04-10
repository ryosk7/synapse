# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    # Primary query tool for the intent-first interface.
    #
    # Claude should:
    #   1. Read the flehmen://catalog resource (or call flehmen_catalog) to see available templates.
    #   2. Interpret the user's intent and select the appropriate template.
    #   3. Call this tool with the template name and required params.
    #
    # The gem validates the plan, compiles it to a safe ActiveRecord query,
    # executes it read-only, and returns PII-masked results.
    class QueryTool < Base
      tool_name "flehmen_query"
      description <<~DESC
        業務データをテンプレートに基づいて安全に検索します。
        利用前に flehmen://catalog リソースまたは flehmen_catalog ツールでテンプレート一覧を確認してください。
        Claude は自由なクエリを組み立てるのではなく、catalog に定義されたテンプレートを選択してください。
      DESC

      arguments do
        required(:template).filled(:string).description(
          "テンプレート名。flehmen_catalog で確認できる名前を指定してください。"
        )
        required(:params).filled(:string).description(
          "テンプレートのパラメータ (JSON オブジェクト)。例: {\"customer_id\": 12345}"
        )
        optional(:options).filled(:string).description(
          "オプション設定 (JSON オブジェクト)。例: {\"limit\": 20, \"order_by\": \"created_at\", \"order_dir\": \"desc\"}"
        )
      end

      def execute(template:, params:, options: nil)
        registry = Flehmen.catalog_registry
        role     = current_user_role

        # Parse incoming JSON strings
        parsed_params  = parse_json(params,  "params")
        parsed_options = options ? parse_json(options, "options") : {}
        return parsed_params  if parsed_params.is_a?(String)   # error message
        return parsed_options if parsed_options.is_a?(String)  # error message

        plan = { template: template, params: parsed_params, options: parsed_options }

        # Validate
        result = Flehmen::Plan::Validator.new(registry, role: role).validate(plan)

        if result.rejected?
          return JSON.generate({
            status: "error",
            errors: result.errors,
            available_templates: registry.template_names.map(&:to_s).sort
          })
        end

        effective_plan = result.effective_plan || plan

        # Compile
        scope = Flehmen::Execution::Compiler.new(registry).compile(effective_plan)

        # Execute
        start_ms = monotonic_ms
        records  = Flehmen::Execution::Runner.new.execute(scope)
        duration = monotonic_ms - start_ms

        # Present
        template_def = registry.find_template(effective_plan[:template])
        presenter    = Flehmen::Presentation::Presenter.new(registry, role: role)
        presented    = presenter.present(records, template_def)
        masked_names = presenter.masked_field_names(template_def)

        # Audit
        Flehmen::Audit::Logger.log(
          template:      effective_plan[:template],
          params:        effective_plan[:params],
          role:          role,
          user:          current_user,
          record_count:  records.size,
          masked_fields: masked_names,
          duration_ms:   duration,
          registry:      registry
        )

        warnings = result.warnings
        warnings += ["#{masked_names.join(', ')} はマスクされています"] if masked_names.any? && result.warnings.none? { |w| w.include?("マスク") }

        JSON.generate({
          status:   result.corrected? ? "corrected" : "success",
          template: effective_plan[:template],
          warnings: warnings,
          data:     presented,
          meta:     {
            count:         records.size,
            limit:         effective_plan.dig(:options, :limit) || Flehmen.configuration.max_results,
            masked_fields: masked_names,
            duration_ms:   duration
          }
        })
      rescue ArgumentError => e
        JSON.generate({ status: "error", errors: [e.message] })
      rescue Flehmen::ReadOnlyViolationError => e
        JSON.generate({ status: "error", errors: ["読み取り専用エラー: #{e.message}"] })
      rescue StandardError => e
        JSON.generate({ status: "error", errors: ["内部エラーが発生しました。管理者に連絡してください。"] })
      end

      private

      def current_user_role
        return nil unless current_user
        return current_user.role.to_s if current_user.respond_to?(:role)

        nil
      end

      def parse_json(str, field_name)
        JSON.parse(str)
      rescue JSON::ParserError => e
        JSON.generate({ status: "error", errors: ["#{field_name} の JSON が不正です: #{e.message}"] })
      end

      def monotonic_ms
        (Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000).to_i
      end
    end
  end
end
