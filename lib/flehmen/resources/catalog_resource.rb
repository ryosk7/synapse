# frozen_string_literal: true

require "json"

module Flehmen
  module Resources
    # MCP Resource that exposes the full catalog definition to Claude.
    #
    # URI: flehmen://catalog
    #
    # Claude can read this resource to discover available templates, their parameters,
    # and which fields each template returns — without needing to call a tool first.
    #
    # This is the preferred way to initialize Claude's context at the start of a session.
    class CatalogResource < FastMcp::Resource
      uri "flehmen://catalog"
      resource_name "Flehmen Catalog"
      description "利用可能なクエリテンプレートとリソース定義の一覧。flehmen_query を使う前にここで確認してください。"
      mime_type "application/json"

      def content
        catalog = Flehmen.catalog_registry.to_catalog_hash
        JSON.pretty_generate(catalog)
      end
    end
  end
end
