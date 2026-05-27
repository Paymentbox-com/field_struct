# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Array type. Coerces each element through the registered element
    # type named by the +:of+ DSL option (resolved at field-declaration
    # time and stashed as +options[:of_type]+ — a class, not a symbol).
    #
    # Missing: +nil+ or empty array. ruby_type: +::Array+.
    class Array < Base
      # @param value [Object] raw input
      # @param options [Hash] must include +:of_type+ (a Types::Base subclass)
      # @return [Array, nil]
      # @raise [TypeError] when input is non-nil and not an Array
      # @raise [KeyError] when +:of_type+ is missing
      # @raise [StandardError] whatever the element type raises on a bad element
      def coerce(value, options = {})
        return nil if value.nil?
        raise ::TypeError, "expected Array, got #{value.class}" unless value.is_a?(::Array)

        element_type = element_type_for(options.fetch(:of_type))
        value.map { |element| element_type.coerce(element) }
      end

      # @param value [Object]
      # @return [Boolean] +true+ when +nil+ or empty
      def missing?(value)
        return true if value.nil?
        return true if value.respond_to?(:empty?) && value.empty?

        false
      end

      # @return [Class] the top-level +::Array+ class
      def ruby_type
        ::Array
      end

      private

      def element_type_for(type_class)
        @element_type_instances ||= {}
        @element_type_instances[type_class] ||= type_class.new
      end
    end
  end
end
