# frozen_string_literal: true

require 'oj'
require_relative 'field_struct/version'
require_relative 'field_struct/error'
require_relative 'field_struct/model_name'
require_relative 'field_struct/types/base'
require_relative 'field_struct/types/string'
require_relative 'field_struct/types/immutable_string'
require_relative 'field_struct/types/integer'
require_relative 'field_struct/types/float'
require_relative 'field_struct/types/big_decimal'
require_relative 'field_struct/types/boolean'
require_relative 'field_struct/types/date'
require_relative 'field_struct/types/time'
require_relative 'field_struct/types/datetime'
require_relative 'field_struct/types/value'
require_relative 'field_struct/types/array'
require_relative 'field_struct/types/nested'
require_relative 'field_struct/types/symbol'
require_relative 'field_struct/types/uuid'
require_relative 'field_struct/types/url'
require_relative 'field_struct/types/email'
require_relative 'field_struct/types/union'
require_relative 'field_struct/types/binary'
require_relative 'field_struct/registry'
require_relative 'field_struct/field'
require_relative 'field_struct/metadata'
require_relative 'field_struct/errors'
require_relative 'field_struct/base'

module FieldStruct
  # Build a new {Registry}, parented to +parent+ (defaults to
  # {FieldStruct.types}), and optionally configure it with a block
  # evaluated in the new registry's instance scope.
  #
  #   module Acme
  #     def self.field_types
  #       @field_types ||= FieldStruct.new_registry do
  #         register :money, Acme::Types::Money
  #       end
  #     end
  #   end
  #
  # Equivalent to the longhand:
  #
  #   FieldStruct::Registry.new(FieldStruct.types).tap do |r|
  #     r.register :money, Acme::Types::Money
  #   end
  #
  # Pass +parent: nil+ for an unparented registry (no fallback chain).
  #
  # @param parent [Registry, nil] the parent registry; defaults to
  #   {FieldStruct.types}. Pass +nil+ explicitly for no parent.
  # @yield evaluated in the new registry's instance scope, so methods
  #   like +register+ / +lookup+ / +key?+ work without an explicit receiver
  # @return [Registry]
  def self.new_registry(parent = types, &block)
    registry = Registry.new(parent)
    registry.instance_eval(&block) if block
    registry
  end

  # The base type registry, seeded with every v1 scalar type and the
  # +:decimal+ alias for +:big_decimal+. Namespace registries should be
  # built with this as their parent (see {Registry}).
  #
  # @return [Registry]
  def self.types
    @types ||= Registry.new.tap do |r|
      r.register :string, Types::String
      r.register :immutable_string, Types::ImmutableString
      r.register :integer, Types::Integer
      r.register :float, Types::Float
      r.register :big_decimal, Types::BigDecimal
      r.register :decimal, :big_decimal
      r.register :boolean, Types::Boolean
      r.register :date, Types::Date
      r.register :time, Types::Time
      r.register :datetime, Types::DateTime
      r.register :value, Types::Value
      r.register :array, Types::Array
      r.register :symbol, Types::Symbol
      r.register :uuid, Types::UUID
      r.register :url, Types::URL
      r.register :email, Types::Email
      r.register :union, Types::Union
      r.register :binary, Types::Binary
    end
  end
end
