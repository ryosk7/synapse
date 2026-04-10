# frozen_string_literal: true

require "fast_mcp"
require_relative "flehmen/version"
require_relative "flehmen/configuration"
require_relative "flehmen/model_registry"
require_relative "flehmen/field_filter"
require_relative "flehmen/query_builder"
require_relative "flehmen/serializer"
require_relative "flehmen/tools/base"
require_relative "flehmen/tools/list_models_tool"
require_relative "flehmen/tools/describe_model_tool"
require_relative "flehmen/tools/find_record_tool"
require_relative "flehmen/tools/search_records_tool"
require_relative "flehmen/tools/count_records_tool"
require_relative "flehmen/tools/show_associations_tool"
require_relative "flehmen/resources/schema_overview_resource"

module Flehmen
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
      server.register_tool(Tools::ListModelsTool)
      server.register_tool(Tools::DescribeModelTool)
      server.register_tool(Tools::FindRecordTool)
      server.register_tool(Tools::SearchRecordsTool)
      server.register_tool(Tools::CountRecordsTool)
      server.register_tool(Tools::ShowAssociationsTool)
    end

    def register_resources(server)
      server.register_resource(Resources::SchemaOverviewResource)
    end
  end
end
