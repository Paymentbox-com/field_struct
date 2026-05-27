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

    # @return [Symbol, nil] this field's coercion-failure policy, or
    #   +nil+ to defer to the class-level setting on {Base.coercion_policy}.
    attr_reader :coercion_policy

    # @param name [Symbol, String]
    # @param type [Class] a Types::Base subclass (already resolved from a symbol)
    # @param type_instance [Types::Base, nil] optional pre-built instance —
    #   used by the DSL for parameterized types (e.g. {Types::Nested}) where
    #   +type.new+ wouldn't be enough to capture the parameterization. When
    #   nil, +type.new+ is called.
    # @param required [Boolean]
    # @param default [Object, #call, nil] literal default value, or a
    #   parameterless callable (Proc/Lambda/Method) that returns one.
    #   Callables are invoked once per instance during apply_defaults.
    # @param coercion_policy [Symbol, nil] override the class-level
    #   coercion policy for this one field; +nil+ means "use whatever the
    #   class says"
    # @param options [Hash] extra type/field options (e.g. +format:+, +of:+)
    def initialize(name:, type:, type_instance: nil, required: false, default: nil,
                   coercion_policy: nil, **options)
      @name = name.to_sym
      @type = type
      @required = required
      @default = default
      @options = options.freeze
      @type_instance = type_instance || type.new
      @coercion_policy = coercion_policy
      freeze
    end

    # @return [Boolean]
    def required?
      @required
    end
  end
end
