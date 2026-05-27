# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Type wrapper for nested FieldStruct fields.
    #
    #   class Address < FieldStruct::Base
    #     required :street, :string
    #     required :city,   :string
    #   end
    #
    #   class Person < FieldStruct::Base
    #     required :address, Address
    #   end
    #
    # Built and held per-Field by the DSL when it sees a class argument
    # that descends from {FieldStruct::Base}. Each instance is
    # parameterized by its target +struct_class+; instances are not
    # interchangeable across different nested classes.
    class Nested < Base
      # @return [Class] the FieldStruct::Base subclass this type wraps
      attr_reader :struct_class

      # @param struct_class [Class] a FieldStruct::Base subclass
      def initialize(struct_class)
        super()
        @struct_class = struct_class
      end

      # Coerce input into a {#struct_class} instance.
      #
      # - +nil+ → +nil+
      # - already a {#struct_class} (or subclass) instance → passthrough
      # - +Hash+ → +struct_class.new(hash)+
      # - anything else → +TypeError+ (which the parent's coercion_policy
      #   handles like any shape-level coercion failure)
      #
      # Errors raised inside +struct_class.new+ (e.g.
      # {UnknownAttributeError}, {CoercionError}) propagate to the caller
      # rather than being caught by the parent's policy — those are
      # structural rejections of the nested record's input, not parent-
      # shape coercion failures.
      #
      # @param value [FieldStruct::Base, Hash, nil] +nil+ → +nil+; an
      #   instance of {#struct_class} (or subclass) → passthrough; a
      #   +Hash+ → constructs via +struct_class.new(hash)+. Anything
      #   else raises TypeError.
      # @return [FieldStruct::Base, nil]
      # @raise [TypeError] when input is non-nil and neither a
      #   {#struct_class} instance nor a Hash
      def coerce(value, **)
        return nil if value.nil?
        return value if value.is_a?(@struct_class)
        return @struct_class.new(value) if value.is_a?(::Hash)

        raise ::TypeError, "expected #{@struct_class} or Hash, got #{value.class}"
      end

      # @param value [Object]
      # @return [Boolean] true only when value is nil — an instance with
      #   all required fields missing is not "missing" here, it is just
      #   invalid. Invalidity is surfaced by the parent's validate_field.
      def missing?(value)
        value.nil?
      end

      # @return [Class] the +struct_class+ itself, so introspection sees
      #   the actual nested type rather than a generic FieldStruct::Base
      def ruby_type
        @struct_class
      end
    end
  end
end
