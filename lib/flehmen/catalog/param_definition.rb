# frozen_string_literal: true

module Flehmen
  module Catalog
    class ParamDefinition
      TYPES = %i[integer string float boolean date].freeze

      attr_reader :name, :type, :required, :default, :description

      def initialize(name, type:, required: true, default: nil, description: nil)
        @name = name.to_sym
        @type = validate_type!(type)
        @required = required
        @default = default
        @description = description
      end

      def optional?
        !@required
      end

      # Coerce a raw input value to the declared type.
      # Returns the default if value is nil and the param is optional.
      # Raises ArgumentError on type mismatch.
      def coerce(value)
        return @default if value.nil? && optional?
        raise ArgumentError, "Missing required param: #{@name}" if value.nil?

        case @type
        when :integer then Integer(value)
        when :float   then Float(value)
        when :string  then value.to_s
        when :boolean then coerce_boolean(value)
        when :date    then coerce_date(value)
        end
      rescue ArgumentError, TypeError => e
        raise ArgumentError, "Invalid value for param '#{@name}' (expected #{@type}): #{e.message}"
      end

      def to_schema_hash
        h = { type: @type.to_s, required: @required }
        h[:description] = @description if @description
        h[:default] = @default unless @default.nil?
        h
      end

      private

      def validate_type!(t)
        t = t.to_sym
        raise ArgumentError, "Unknown param type: #{t}. Valid: #{TYPES.join(', ')}" unless TYPES.include?(t)

        t
      end

      def coerce_boolean(value)
        return value if value == true || value == false
        return true  if value.to_s =~ /\A(true|yes|1)\z/i
        return false if value.to_s =~ /\A(false|no|0)\z/i

        raise ArgumentError, "cannot coerce '#{value}' to boolean"
      end

      def coerce_date(value)
        return value if value.is_a?(Date)

        Date.parse(value.to_s)
      end
    end
  end
end
