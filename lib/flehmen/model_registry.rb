# frozen_string_literal: true

module Flehmen
  class ModelRegistry
    attr_reader :models

    def initialize(config = Flehmen.configuration)
      @config = config
      @models = {}
    end

    def discover!
      base_class = defined?(ApplicationRecord) ? ApplicationRecord : ActiveRecord::Base
      raw_models = if @config.models == :all
                     base_class.descendants
                   else
                     @config.models.map { |m| m.is_a?(String) ? m.constantize : m }
                   end

      excluded = @config.exclude_models.map { |m| m.is_a?(String) ? m.constantize : m }

      raw_models.each do |klass|
        next if klass.abstract_class?
        next if excluded.include?(klass)
        next unless safe_table_exists?(klass)

        register(klass)
      rescue StandardError
        # Skip models that fail introspection (e.g., STI subclasses with missing tables)
        next
      end

      self
    end

    def model_names
      @models.keys.sort
    end

    def find_model(name)
      @models[name] || @models[name.to_s.classify]
    end

    private

    def safe_table_exists?(klass)
      klass.table_exists?
    rescue StandardError
      false
    end

    def register(klass)
      @models[klass.name] = {
        klass: klass,
        table_name: klass.table_name,
        columns: extract_columns(klass),
        associations: extract_associations(klass),
        enums: extract_enums(klass),
        primary_key: klass.primary_key
      }
    end

    def extract_columns(klass)
      klass.columns.map do |col|
        {
          name: col.name,
          type: col.type.to_s,
          null: col.null,
          default: col.default,
          limit: col.limit
        }
      end
    end

    def extract_associations(klass)
      klass.reflect_on_all_associations.map do |assoc|
        {
          name: assoc.name.to_s,
          type: assoc.macro.to_s,
          class_name: assoc.class_name,
          foreign_key: assoc.foreign_key.to_s,
          through: assoc.options[:through]&.to_s,
          polymorphic: assoc.options[:polymorphic] || false
        }
      end
    end

    def extract_enums(klass)
      return {} unless klass.respond_to?(:defined_enums)

      klass.defined_enums.transform_values(&:keys)
    end
  end
end
