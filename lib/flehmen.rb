# frozen_string_literal: true

require "fast_mcp"
require_relative "flehmen/version"
require_relative "flehmen/configuration"
require_relative "flehmen/model_registry"
require_relative "flehmen/field_filter"
require_relative "flehmen/query_builder"
require_relative "flehmen/serializer"

# Catalog layer
require_relative "flehmen/catalog/field_definition"
require_relative "flehmen/catalog/param_definition"
require_relative "flehmen/catalog/filter_definition"
require_relative "flehmen/catalog/resource_definition"
require_relative "flehmen/catalog/template_definition"
require_relative "flehmen/catalog/policy_definition"
require_relative "flehmen/catalog/registry"

# Plan layer
require_relative "flehmen/plan/validation_result"
require_relative "flehmen/plan/validator"

# Execution layer
require_relative "flehmen/execution/compiler"
require_relative "flehmen/execution/runner"

# Presentation layer
require_relative "flehmen/presentation/masker"
require_relative "flehmen/presentation/presenter"

# Audit layer
require_relative "flehmen/audit/logger"

# MCP tools & resources
require_relative "flehmen/tools/base"
require_relative "flehmen/tools/query_tool"
require_relative "flehmen/tools/catalog_tool"
# Legacy tools (deprecated — will be removed in a future version)
require_relative "flehmen/tools/list_models_tool"
require_relative "flehmen/tools/describe_model_tool"
require_relative "flehmen/tools/find_record_tool"
require_relative "flehmen/tools/search_records_tool"
require_relative "flehmen/tools/count_records_tool"
require_relative "flehmen/tools/show_associations_tool"
require_relative "flehmen/resources/catalog_resource"
require_relative "flehmen/resources/schema_overview_resource"

module Flehmen
  # Raised when a write operation is attempted in read-only mode.
  ReadOnlyViolationError = Class.new(StandardError)

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset_configuration!
      @configuration = Configuration.new
      @model_registry = nil
    end

    # Catalog DSL entry point.
    #
    #   Flehmen.catalog do |c|
    #     c.resource :Customer, model: "Customer" do |r|
    #       r.field :id,    classification: :public
    #       r.field :email, classification: :personal, mask: :email
    #     end
    #
    #     c.template :customer_overview do |t|
    #       t.description "顧客基本情報"
    #       t.resource :Customer
    #       t.fields [:id, :email]
    #       t.param :customer_id, type: :integer, required: true
    #       t.filter :by_id, field: :id, operator: :eq, param: :customer_id
    #     end
    #
    #     c.policy :support do |p|
    #       p.allow_templates :customer_overview
    #       p.max_results 50
    #     end
    #   end
    def catalog(&block)
      yield(catalog_registry) if block_given?
      catalog_registry
    end

    def catalog_registry
      @catalog_registry ||= Catalog::Registry.new
    end

    def reset_catalog!
      @catalog_registry = Catalog::Registry.new
    end

    # Lazily discover models on first access
    def model_registry
      @model_registry || boot!
    end

    def boot!
      @model_registry = ModelRegistry.new(configuration)
      @model_registry.discover!
    end

    def start_server!
      configuration.validate!
      server = build_server
      server.start
    end

    # NOTE: This is the main entry point for mounting Flehmen as Rack middleware
    # in a Rails application. Call this in your Rails initializer to register
    # all MCP tools and resources with the FastMcp transport layer.
    def catloaf(app, options = {})
      configuration.validate!

      opts = {
        name: "flehmen",
        version: Flehmen::VERSION,
        path_prefix: options.delete(:path_prefix) || "/mcp"
      }.merge(options)

      if configuration.auth_token
        opts[:authenticate] = true
        opts[:auth_token] = configuration.auth_token
      end

      FastMcp.mount_in_rails(app, opts) do |server|
        register_tools(server)
        register_resources(server)
        setup_auth_filters(server) if configuration.authenticate
      end
    end

    private

    def setup_auth_filters(server)
      auth_proc = configuration.authenticate

      server.filter_tools do |request, tools|
        headers = extract_headers(request)
        auth_proc.call(headers) ? tools : []
      end

      server.filter_resources do |request, resources|
        headers = extract_headers(request)
        auth_proc.call(headers) ? resources : []
      end
    end

    def extract_headers(request)
      request.env.select { |k, _| k.start_with?("HTTP_") }
                 .transform_keys { |k| k.sub("HTTP_", "").downcase.tr("_", "-") }
    end

    def build_server
      server = FastMcp::Server.new(
        name: "flehmen",
        version: Flehmen::VERSION
      )
      register_tools(server)
      register_resources(server)
      server
    end

    def register_tools(server)
      # Intent-first tools (v2)
      server.register_tool(Tools::QueryTool)
      server.register_tool(Tools::CatalogTool)
      # Legacy query-first tools (deprecated)
      server.register_tool(Tools::ListModelsTool)
      server.register_tool(Tools::DescribeModelTool)
      server.register_tool(Tools::FindRecordTool)
      server.register_tool(Tools::SearchRecordsTool)
      server.register_tool(Tools::CountRecordsTool)
      server.register_tool(Tools::ShowAssociationsTool)
    end

    def register_resources(server)
      server.register_resource(Resources::CatalogResource)
      server.register_resource(Resources::SchemaOverviewResource)
    end
  end
end
