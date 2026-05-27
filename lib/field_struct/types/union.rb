# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Union type — a value that may be any of several types. Each
    # member is tried in declared order; the first one whose +coerce+
    # doesn't raise wins. Member-coercion errors are caught broadly
    # (ArgumentError, TypeError, FieldStruct::Error) so a member's
    # rejection lets the next member have a try; unrelated bugs (e.g.
    # +NoMethodError+) still propagate.
    #
    #   optional :payload, :union, of: [Payload, :boolean]
    #
    # If every member rejects the value, the union raises a +TypeError+
    # which the parent's +coercion_policy+ handles like any
    # shape-level coercion failure.
    #
    # Order matters: +of: [String, Integer]+ coerces "42" to "42"
    # (String wins first); +of: [Integer, String]+ coerces "42" to 42.
    class Union < Base
      RESCUABLE = [ArgumentError, TypeError, FieldStruct::Error].freeze

      # @return [Array<Types::Base>] the configured member type instances
      attr_reader :member_types

      # @param member_types [Array<Types::Base>] member instances, in priority order
      def initialize(member_types)
        super()
        @member_types = member_types
      end

      # @param value [Object]
      # @return [Object, nil]
      # @raise [TypeError] when no member can coerce
      def coerce(value, **)
        return nil if value.nil?

        @member_types.each do |type|
          return type.coerce(value)
        rescue *RESCUABLE
          next
        end

        raise ::TypeError, "no union member could coerce #{value.inspect}"
      end

      # @param value [Object]
      # @return [Boolean] true only for nil — union doesn't try to
      #   collectively reason about "missing" across its members
      def missing?(value)
        value.nil?
      end

      # Flat list of member +ruby_type+ values. Members whose
      # ruby_type is already an Array (like Boolean's
      # +[TrueClass, FalseClass]+) get spliced in; duplicates are
      # removed.
      #
      # @return [Array<Class>]
      def ruby_type
        @member_types.flat_map { |type| Array(type.ruby_type) }.uniq
      end
    end
  end
end
