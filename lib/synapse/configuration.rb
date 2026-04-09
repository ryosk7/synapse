# frozen_string_literal: true

module Synapse
  class Configuration
    attr_accessor :models,
                  :exclude_models,
                  :sensitive_fields,
                  :model_sensitive_fields,
                  :max_results,
                  :enable_raw_sql,
                  :read_only_connection

    def initialize
      @models = :all
      @exclude_models = []
      @sensitive_fields = %i[
        password_digest encrypted_password token secret
        api_key api_secret access_token refresh_token
        otp_secret reset_password_token confirmation_token
        unlock_token remember_token authentication_token
      ]
      @model_sensitive_fields = {}
      @max_results = 100
      @enable_raw_sql = false
      @read_only_connection = true
    end
  end
end
