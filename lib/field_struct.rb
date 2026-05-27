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
require_relative 'field_struct/registry'
require_relative 'field_struct/field'
require_relative 'field_struct/metadata'
require_relative 'field_struct/errors'
require_relative 'field_struct/base'

module FieldStruct
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
    end
  end
end
