# frozen_string_literal: true

module FieldStruct
  # A single declared attribute on a FieldStruct class.
  #
  # Holds the field's name, the resolved type class, whether it's
  # required, an optional default, and any remaining keyword options
  # (e.g. +format:+). Frozen after construction — the DSL is expected
  # to build a fresh Field rather than mutate one.
  class Field
    # @return [Symbol]
    attr_reader :name

    # @return [Class] a subclass of {Types::Base}
    attr_reader :type

    # @return [Object, nil] the configured default value, or +nil+ if none
    attr_reader :default

    # @return [Hash] frozen, holds the remaining keyword options
    attr_reader :options

    # @return [Types::Base] an eagerly-built instance of {#type}, reused by
    #   the setter pipeline so we don't allocate a fresh type per coercion
    attr_reader :type_instance

    # @param name [Symbol, String]
    # @param type [Class] a Types::Base subclass (already resolved from a symbol)
    # @param required [Boolean]
    # @param default [Object, nil]
    # @param options [Hash] extra type/field options (e.g. +format:+, +of:+)
    def initialize(name:, type:, required: false, default: nil, **options)
      @name = name.to_sym
      @type = type
      @required = required
      @default = default
      @options = options.freeze
      @type_instance = type.new
      freeze
    end

    # @return [Boolean]
    def required?
      @required
    end
  end
end
