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

    # @return [Hash{Symbol=>Object, nil}] frozen, holds the remaining keyword
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

    # @return [String, nil] an RBS type expression that {RBS.generate} and
    #   {RBS.type_for} emit for this field instead of deriving one from the
    #   type (e.g. +"::ActiveRecord::Relation"+ on a +:value+ field), or
    #   +nil+ to derive it. Declared with the +rbs_type:+ field option;
    #   signatures only — it never affects coercion or validation.
    attr_reader :rbs_type

    # @api private
    # @return [Symbol] the setter's method name (+:name=+), built once here
    #   so the setter pipeline doesn't intern a dynamic Symbol per call
    attr_reader :setter_name

    # @api private
    # @return [Symbol] the instance variable holding the value (+:@name+),
    #   built once for the same reason as {#setter_name}
    attr_reader :ivar_name

    # @param name [Symbol, String] canonical field name
    # @param type [Class<Types::Base>] the resolved type class
    # @param type_instance [Types::Base, nil] optional pre-built instance —
    #   used by the DSL for parameterized types (e.g. {Types::Nested}) where
    #   +type.new+ wouldn't be enough to capture the parameterization. When
    #   nil, +type.new+ is called.
    # @param required [Boolean]
    # @param default [Object, nil] literal default value, or a
    #   parameterless callable (Proc/Lambda/Method) that returns one.
    #   Callables are invoked once per instance during apply_defaults.
    # @param coercion_policy [:keep_raw, :replace, :raise, nil] override
    #   the class-level coercion policy for this one field; +nil+ means
    #   "use whatever the class says"
    # @param description [String, nil] human-readable description of the
    #   field; for documentation purposes only
    # @param rbs_type [String, nil] RBS type expression overriding the
    #   derived one in generated signatures (see {#rbs_type})
    # @param sensitive [Boolean] mask the value in {Base#inspect} (see {#sensitive?})
    # @param options [Object, nil] extra keyword type/field options
    #   forwarded to coerce (e.g. +format:+, +of_type:+, +round:+,
    #   +values:+, +enum:+, +in:+)
    def initialize(name:, type:, type_instance: nil, required: false, default: nil, coercion_policy: nil, description: nil, rbs_type: nil, sensitive: false, **options)
      @name = name.to_sym
      @setter_name = :"#{@name}="
      @ivar_name = :"@#{@name}"
      @type = type
      @required = required
      @default = default
      @options = options.freeze
      @type_instance = type_instance || type.new
      @coercion_policy = coercion_policy
      @description = description
      @rbs_type = rbs_type
      @sensitive = sensitive
      freeze
    end

    # @return [Boolean]
    def required?
      @required
    end

    # Whether the field holds data that must not reach a log — a card
    # number, a CVV, a token. {Base#inspect} (and so +pp+) renders
    # {FieldStruct::FILTERED} in place of a non-nil value. Data paths —
    # the reader, +attributes+, +to_h+, +as_json+, +to_json+, pattern
    # matching — return the real value, so round-trips stay exact.
    # Declared with the +sensitive:+ field option.
    #
    # @return [Boolean]
    def sensitive?
      @sensitive
    end

    # @return [String, nil] shorter alias of {#description}
    alias desc description

    # Concise one-line representation. Designed to be readable in IRB
    # without dumping every ivar (the default Object#inspect is the
    # reason +optional :x, :string+ in a console looks like a wall of
    # text).
    #
    # @return [String]
    def inspect
      parts = [@name.inspect, type_repr]
      parts << 'required' if @required
      parts << 'sensitive' if @sensitive
      parts << "default=#{@default.inspect}" unless @default.nil?
      parts << "coercion_policy=#{@coercion_policy.inspect}" if @coercion_policy
      parts << "description=#{@description.inspect}" if @description
      parts << "rbs_type=#{@rbs_type.inspect}" if @rbs_type
      @options.each { |key, value| parts << "#{key}=#{option_repr(value)}" }
      "#<#{FieldStruct.inspect_namespace}::Field #{parts.join(" ")}>"
    end

    # Delegates pretty-print to {#inspect} so IRB / pp don't fall back
    # to the default reflection-based output.
    #
    # @param pp [Object] a PP-shaped sink (responds to +#text+)
    # @return [void]
    def pretty_print(pp)
      pp.text(inspect)
    end

    private

    # @return [String] the type's short name, or +Nested(...)+ / +Union(...)+
    def type_repr
      base = @type.name.to_s.split('::').last
      if @type <= FieldStruct::Types::Nested
        "Nested(#{@type_instance.struct_class.name || "AnonymousFieldStruct"})"
      elsif @type <= FieldStruct::Types::Union
        members = @type_instance.member_types.map { |m| m.class.name.to_s.split('::').last }
        "Union(#{members.join(" | ")})"
      else
        base
      end
    end

    # Render an option's value in inspect output. Type-class values
    # (e.g. +:of_type+ on an Array field) get their basename instead
    # of the full +FieldStruct::Types::String+ class.inspect.
    #
    # @param value [Object, nil] an option value
    # @return [String]
    def option_repr(value)
      case value
      when ::Class
        value.name.to_s.split('::').last
      when FieldStruct::Types::Nested
        "Nested(#{value.struct_class.name || "AnonymousFieldStruct"})"
      when FieldStruct::Types::Base
        value.class.name.to_s.split('::').last
      # Spelled out rather than Hash#inspect, whose format changed in Ruby 3.4.
      when ::Hash
        "{#{value.map { |key, item| "#{key}: #{option_repr(item)}" }.join(", ")}}"
      else
        value.inspect
      end
    end
  end
end
