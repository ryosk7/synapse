# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    class ExecuteQueryTool < FastMcp::Tool
      tool_name "flehmen_execute_query"
      description "Execute a read-only SQL SELECT query. Only available if enabled in configuration. Only SELECT statements are allowed."

      FORBIDDEN_KEYWORDS = %w[
        INSERT UPDATE DELETE DROP ALTER CREATE TRUNCATE
        GRANT REVOKE REPLACE MERGE CALL EXEC EXECUTE
        SET LOCK UNLOCK
      ].freeze

      arguments do
        required(:sql).filled(:string).description("SQL SELECT query to execute")
        optional(:limit).filled(:integer).description("Max rows to return (default: server max_results)")
      end

      annotations(
        read_only_hint: true,
        open_world_hint: false
      )

      def call(sql:, limit: nil)
        unless Flehmen.configuration.enable_raw_sql
          return JSON.generate({ error: "Raw SQL execution is disabled. Set config.enable_raw_sql = true to enable." })
        end

        normalized = sql.gsub(/--[^\n]*/, "").gsub(%r{/\*.*?\*/}m, "").strip

        unless normalized.match?(/\ASELECT\b/i)
          return JSON.generate({ error: "Only SELECT statements are allowed" })
        end

        if FORBIDDEN_KEYWORDS.any? { |kw| normalized.match?(/\b#{kw}\b/i) }
          return JSON.generate({ error: "Query contains forbidden keywords" })
        end

        max = Flehmen.configuration.max_results
        effective_limit = limit ? [limit.to_i, max].min : max

        unless normalized.match?(/\bLIMIT\b/i)
          normalized = "#{normalized} LIMIT #{effective_limit}"
        end

        result = ActiveRecord::Base.connection.exec_query(normalized)

        filter = Flehmen::FieldFilter.new
        rows = result.to_a.map do |row|
          filter.filter_attributes("_raw_sql", row)
        end

        JSON.generate({
          columns: result.columns,
          rows: rows,
          count: rows.size
        })
      rescue ActiveRecord::StatementInvalid => e
        JSON.generate({ error: "SQL error: #{e.message}" })
      end
    end
  end
end
