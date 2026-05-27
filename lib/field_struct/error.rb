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
end
