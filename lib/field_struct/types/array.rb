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
      # Native options: a required +of:+ naming the element type — a
      # registered Symbol or a Class (a +Types::Base+ or +FieldStruct::Base+
      # subclass).
      #
      # @return [Hash{Symbol=>Hash}]
      def self.option_schema
        super.merge(of: option(type: [::Symbol, ::Class], required: true))
      end

      # @param value [Array, nil] anything else raises TypeError
      # @param of_type [Class, Types::Base, nil] the element type — a
      #   Types::Base subclass for stock types, or an already-built
      #   instance for parameterized types like {Types::Nested}. The DSL
      #   stashes this when the user writes +of: :string+ / +of: SomeStruct+.
      #   Required at the type level; nil here means the type was called
      #   directly without DSL help.
      # @return [Array, nil]
      # @raise [TypeError] when input is non-nil and not an Array
      # @raise [ArgumentError] when +of_type+ is missing
      # @raise [StandardError] whatever the element type raises on a bad element
      def coerce(value, of_type: nil, **)
        return nil if value.nil?
        raise ::TypeError, "expected Array, got #{value.class}" unless value.is_a?(::Array)
        raise ArgumentError, 'array coerce requires of_type:' if of_type.nil?

        element_type = element_type_for(of_type)
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

      # +of_type+ may be either a Types::Base subclass (the DSL form for
      # stock types like +:string+) or an already-built Types::Base
      # instance (the DSL form for parameterized types like
      # {Types::Nested}). Both produce a single cached instance per
      # configured element type.
      def element_type_for(type_or_instance)
        return type_or_instance unless type_or_instance.is_a?(::Class)

        @element_type_instances ||= {}
        @element_type_instances[type_or_instance] ||= type_or_instance.new
      end
    end
  end
end
