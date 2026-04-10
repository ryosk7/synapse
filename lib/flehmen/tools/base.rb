# frozen_string_literal: true

module Flehmen
  module Tools
    class Base < FastMcp::Tool
      attr_reader :current_user

      authorize do
        auth_proc = Flehmen.configuration.authenticate
        next true unless auth_proc
        next true if headers.nil? || headers.empty?

        result = auth_proc.call(headers)
        @current_user = result
        !!result
      end

      def call(**args)
        ActiveRecord::Base.while_preventing_writes(Flehmen.configuration.read_only_connection) do
          execute(**args)
        end
      end
    end
  end
end
