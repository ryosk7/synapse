# frozen_string_literal: true

require "json"

module Flehmen
  module Tools
    # Returns the catalog of available templates and resources for the current user's role.
    #
    # Claude should call this tool at the start of a session (or when uncertain which
    # template to use) to discover what's available before calling flehmen_query.
    #
    # Alternatively, Claude can read the flehmen://catalog resource for the same information.
    class CatalogTool < Base
      tool_name "flehmen_catalog"
      description <<~DESC
        利用可能なクエリテンプレートの一覧を返します。
        flehmen_query を呼ぶ前にこのツールでテンプレート名とパラメータを確認してください。
        ロールに応じてアクセス可能なテンプレートのみ返されます。
      DESC

      arguments do
        optional(:type).filled(:string).description(
          "返す情報の種類: 'templates'（デフォルト）, 'resources', 'all'"
        )
      end

      def execute(type: "templates")
        registry = Flehmen.catalog_registry
        role     = current_user_role

        catalog = registry.to_catalog_hash(role: role)

        result = case type.to_s
                 when "resources" then { resources: catalog[:resources] }
                 when "all"       then catalog
                 else                  { templates: catalog[:templates] }
                 end

        JSON.generate(result)
      end

      private

      def current_user_role
        return nil unless current_user
        return current_user.role.to_s if current_user.respond_to?(:role)

        nil
      end
    end
  end
end
