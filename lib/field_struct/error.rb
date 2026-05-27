# frozen_string_literal: true

module FieldStruct
  # Base class for every error FieldStruct raises. Catch this to handle
  # any library error generically.
  class Error < StandardError; end

  # Raised by the setter pipeline when a value cannot be coerced into a
  # field's declared type and the class's +coercion_policy+ is +:raise+.
  #
  # Carries the field name and the original underlying error for callers
  # that want to inspect what happened.
  class CoercionError < Error
    # @return [Symbol, nil]
    attr_reader :field_name

    # @return [Exception, nil] the underlying error from the type's coerce
    attr_reader :original

    # @param message [String]
    # @param field_name [Symbol, nil]
    # @param original [Exception, nil]
    def initialize(message, field_name: nil, original: nil)
      super(message)
      @field_name = field_name
      @original = original
    end
  end

  # Raised when a field setter on a class marked +immutable!+ is called
  # after construction.
  class ImmutableError < Error; end

  # Raised by {Base#initialize} / {Base#assign_attributes} when the input
  # hash includes a key that is not a declared field on the class and
  # the +unknown_attributes+ policy is +:raise+.
  class UnknownAttributeError < Error
    # @return [Array<Symbol>] the offending keys
    attr_reader :keys

    # @param message [String]
    # @param keys [Array<Symbol>]
    def initialize(message, keys: [])
      super(message)
      @keys = keys
    end
  end
end
