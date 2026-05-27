# frozen_string_literal: true

module FieldStruct
  # A single declared attribute on a FieldStruct class.
  #
  # Holds the field's name, the resolved type class, whether it's
  # required, an optional default, and any remaining keyword options
  # (e.g. +format:+). Frozen after construction — the DSL is expected
  # to build a fresh Field rather than mutate one.
  class Field
    # @return [Symbol] canonical field name
    attr_reader :name

    # @return [Class<Types::Base>] the resolved type class
    attr_reader :type

    # @return [Object, #call, nil] the configured default value, or a
    #   parameterless callable returning one, or +nil+ if no default
    attr_reader :default

    # @return [Hash{Symbol=>Object}] frozen, holds the remaining keyword
    #   options forwarded to {Types::Base#coerce} (e.g. +:format+,
    #   +:round+, +:values+, +:of_type+, +:enum+, +:in+)
    attr_reader :options

    # @return [Types::Base] an eagerly-built instance of {#type}, reused by
    #   the setter pipeline so we don't allocate a fresh type per coercion
    attr_reader :type_instance

    # @return [:keep_raw, :replace, :raise, nil] this field's coercion-
    #   failure policy override, or +nil+ to defer to the class-level
    #   setting on {Base.coercion_policy}.
    attr_reader :coercion_policy

    # @return [String, nil] human-readable description of the field;
    #   intended for downstream documentation generators. Not part of
    #   the data surface — does not appear in +attributes+ / +as_json+ /
    #   pattern matches.
    attr_reader :description

    # @param name [Symbol, String] canonical field name
    # @param type [Class<Types::Base>] the resolved type class
    # @param type_instance [Types::Base, nil] optional pre-built instance —
    #   used by the DSL for parameterized types (e.g. {Types::Nested}) where
    #   +type.new+ wouldn't be enough to capture the parameterization. When
    #   nil, +type.new+ is called.
    # @param required [Boolean]
    # @param default [Object, #call, nil] literal default value, or a
    #   parameterless callable (Proc/Lambda/Method) that returns one.
    #   Callables are invoked once per instance during apply_defaults.
    # @param coercion_policy [:keep_raw, :replace, :raise, nil] override
    #   the class-level coercion policy for this one field; +nil+ means
    #   "use whatever the class says"
    # @param description [String, nil] human-readable description of the
    #   field; for documentation purposes only
    # @param options [Hash{Symbol=>Object}] extra type/field options
    #   forwarded to coerce (e.g. +format:+, +of_type:+, +round:+,
    #   +values:+, +enum:+, +in:+)
    def initialize(name:, type:, type_instance: nil, required: false, default: nil,
                   coercion_policy: nil, description: nil, **options)
      @name = name.to_sym
      @type = type
      @required = required
      @default = default
      @options = options.freeze
      @type_instance = type_instance || type.new
      @coercion_policy = coercion_policy
      @description = description
      freeze
    end

    # @return [Boolean]
    def required?
      @required
    end

    # @return [String, nil] shorter alias of {#description}
    alias desc description
  end
end
