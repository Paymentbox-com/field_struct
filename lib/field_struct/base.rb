# frozen_string_literal: true

module FieldStruct
  # Superclass for FieldStruct value classes.
  #
  #   class User < FieldStruct::Base
  #     field :name, :string
  #     field :age,  :integer
  #   end
  #
  #   u = User.new(name: 'Alice', age: '30')
  #   u.name        # => 'Alice'
  #   u.age         # => 30   (coerced from the string)
  #   u.attributes  # => { name: 'Alice', age: 30 }
  #
  # Phase 1 wires up the +field+ macro, getter/setter accessors with
  # coercion via the resolved type, +initialize+ from a hash, +attributes+
  # / +attribute_names+, and metadata inheritance via the +inherited+
  # hook. Macros and validation layer on in later slices.
  class Base
    VALID_COERCION_POLICIES = %i[keep_raw replace raise].freeze
    VALID_UNKNOWN_POLICIES = %i[ignore raise].freeze
    UNSET = Object.new.freeze
    private_constant :UNSET

    class << self
      # @return [Metadata] the per-class field collection (memoized)
      def metadata
        @metadata ||= Metadata.new
      end

      # Mark this class (and its descendants) immutable. Setters called
      # after {#initialize} completes raise {ImmutableError}. One-way
      # switch: there is no companion +mutable!+ macro in Phase 1.
      #
      # @return [true]
      def immutable!
        @immutable = true
      end

      # @return [Boolean] whether this class is marked immutable
      #   (locally or via an ancestor)
      def immutable?
        return @immutable if defined?(@immutable)
        return superclass.immutable? if superclass.respond_to?(:immutable?)

        false
      end

      # Class macro: get or set the policy used by the setter pipeline
      # when a value can't be coerced into a field's declared type.
      #
      #   coercion_policy :keep_raw   # default — store raw, add error
      #   coercion_policy :replace    # store nil,  add error
      #   coercion_policy :raise      # raise CoercionError
      #
      # Inherited by subclasses; descendants can override. Default on
      # Base itself is +:keep_raw+.
      #
      # @param value [Symbol, UNSET]
      # @return [Symbol]
      def coercion_policy(value = UNSET)
        if value.equal?(UNSET)
          return @coercion_policy if defined?(@coercion_policy)
          return superclass.coercion_policy if superclass.respond_to?(:coercion_policy)

          :keep_raw
        else
          unless VALID_COERCION_POLICIES.include?(value)
            raise ArgumentError, "unknown coercion policy #{value.inspect} " \
                                 "(expected one of #{VALID_COERCION_POLICIES.inspect})"
          end

          @coercion_policy = value
        end
      end

      # Class macro: get or set how {Base#initialize} responds to input
      # keys that do not match any declared field.
      #
      #   unknown_attributes :ignore   # default — silently drop them
      #   unknown_attributes :raise    # raise UnknownAttributeError
      #
      # Inherited by subclasses; descendants can override.
      #
      # @param value [Symbol, UNSET]
      # @return [Symbol]
      def unknown_attributes(value = UNSET)
        if value.equal?(UNSET)
          return @unknown_attributes if defined?(@unknown_attributes)
          return superclass.unknown_attributes if superclass.respond_to?(:unknown_attributes)

          :ignore
        else
          unless VALID_UNKNOWN_POLICIES.include?(value)
            raise ArgumentError, "unknown unknown_attributes policy #{value.inspect} " \
                                 "(expected one of #{VALID_UNKNOWN_POLICIES.inspect})"
          end

          @unknown_attributes = value
        end
      end

      # @return [Array<Symbol>] declared field names in insertion order
      def attribute_names
        metadata.names
      end

      # Declare a field. Resolves +type_name+ via the registry chain (the
      # nearest containing module that responds to +field_types+, falling
      # back to {FieldStruct.types}), builds a {Field}, adds it to the
      # class's {Metadata}, and defines the getter/setter pair.
      #
      # @param name [Symbol, String]
      # @param type_name [Symbol] a name registered in the resolved registry
      # @param options [Hash] +required:+, +default:+, plus type-specific options
      # @return [Field] the field that was added
      def field(name, type_name, **options)
        type_class = resolve_type(type_name)
        resolve_array_options!(type_class, options)
        validate_format_option!(type_class, options)
        required = options.delete(:required) { false }
        default = options.delete(:default)
        field = Field.new(name: name, type: type_class, required: required, default: default, **options)
        metadata.add(field)
        define_field_accessors(field)
        field
      end

      # Sugar for {#field} with +required: true+.
      def required(name, type_name, **options)
        field(name, type_name, **options, required: true)
      end

      # Sugar for {#field} with +required: false+ (the default).
      def optional(name, type_name, **options)
        field(name, type_name, **options, required: false)
      end

      # Resolve a type name through the registry chain visible to this
      # class. Walks the containing modules of the class's name in
      # outermost-first order, looking for the nearest one that responds
      # to +field_types+. Falls back to {FieldStruct.types}.
      #
      # @param type_name [Symbol]
      # @return [Class] a Types::Base subclass
      def resolve_type(type_name)
        registry = namespace_field_types || FieldStruct.types
        registry.lookup(type_name)
      end

      # @return [ModelName] an ActiveModel::Name-shaped value for this class
      def model_name
        @model_name ||= ModelName.new(name)
      end

      private

      def namespace_field_types
        return nil unless name

        parts = name.split('::')
        parts.pop # drop the class's own name

        until parts.empty?
          mod = ::Object.const_get(parts.join('::'))
          return mod.field_types if mod.respond_to?(:field_types)

          parts.pop
        end

        nil
      end

      def resolve_array_options!(type_class, options)
        return unless type_class <= FieldStruct::Types::Array
        raise ArgumentError, 'array field requires an `of:` option naming the element type' unless options.key?(:of)

        options[:of_type] = resolve_type(options.delete(:of))
      end

      def validate_format_option!(type_class, options)
        return unless options.key?(:format)
        return if type_class <= FieldStruct::Types::String

        raise ArgumentError,
          "format: option only applies to string-shaped fields (string, immutable_string), not #{type_class}"
      end

      def define_field_accessors(field)
        attr_reader field.name

        define_method(:"#{field.name}=") do |value|
          if @_initialized && self.class.immutable?
            raise ImmutableError, "#{self.class} is immutable; cannot reassign #{field.name}"
          end

          begin
            coerced = field.type_instance.coerce(value, field.options)
          rescue ArgumentError, TypeError => e
            return apply_coercion_policy(field, value, e)
          end

          instance_variable_set(:"@#{field.name}", coerced)
          validate_field(field, coerced)
          coerced
        end
      end

      def inherited(subclass)
        super
        subclass.metadata.merge(metadata)
      end
    end

    # @param attrs [Hash{Symbol,String=>Object}] input values, by symbol or string key
    def initialize(attrs = {})
      @errors = Errors.new
      apply_defaults
      assign_attributes(attrs)
      @_initialized = true
    end

    # Bulk-update declared attributes from a hash. Routes each value
    # through the same setter pipeline used everywhere else — so coercion,
    # presence checks, and the +coercion_policy+ all run as normal.
    #
    # Respects {.unknown_attributes} on input and {.immutable?} on the
    # setter side. The same method that powers {#initialize} is exposed
    # here for callers that want to update many attributes at once.
    #
    # @param attrs [Hash{Symbol,String=>Object}]
    # @return [self]
    def assign_attributes(attrs)
      reject_unknown_attributes!(attrs)
      attrs.each do |key, value|
        sym = key.to_sym
        next unless self.class.metadata[sym]

        public_send(:"#{sym}=", value)
      end
      self
    end

    # @return [Hash{Symbol=>Object}] a fresh hash of current attribute values
    def attributes
      self.class.metadata.to_h { |field| [field.name, public_send(field.name)] }
    end

    # @return [Array<Symbol>]
    def attribute_names
      self.class.attribute_names
    end

    # @return [Errors] the per-instance error collection
    def errors
      @errors ||= Errors.new
    end

    # @return [Boolean] true when {#errors} is empty
    def valid?
      errors.empty?
    end

    # @return [Boolean] true when {#valid?} is false
    def invalid?
      !valid?
    end

    # Structural equality: same class AND same {#attributes}. Errors are
    # ignored — equality is about value, not validity.
    #
    # @param other [Object]
    # @return [Boolean]
    def ==(other)
      other.instance_of?(self.class) && attributes == other.attributes
    end
    alias eql? ==

    # @return [Integer] consistent with {#==} so instances work as Hash
    #   keys and Set members
    def hash
      [self.class, attributes].hash
    end

    # @return [Hash{Symbol=>Object}] alias of {#attributes}
    def to_h
      attributes
    end

    # @param _options [Object] unused — accepted for ActiveSupport-style symmetry
    # @return [Hash{Symbol=>Object}] a JSON-ready hash. Date/Time/DateTime
    #   convert to ISO-8601 strings, BigDecimal to its plain-form string,
    #   Symbol to String. Arrays recurse.
    def as_json(_options = nil)
      attributes.transform_values { |value| json_value(value) }
    end

    # @return [String] JSON representation, via Oj
    def to_json(_options = nil)
      Oj.dump(as_json, mode: :compat)
    end

    # @return [String] +#<ClassName field: value, ...>+
    def inspect
      pairs = attributes.map { |name, value| "#{name}: #{value.inspect}" }.join(', ')
      "#<#{self.class.name || "AnonymousFieldStruct"} #{pairs}>"
    end

    # @return [ModelName]
    def model_name
      self.class.model_name
    end

    # @return [self] for ActiveModel-shaped helpers that call .to_model
    def to_model
      self
    end

    private

    def json_value(value)
      case value
      when nil, true, false, ::String, ::Integer, ::Float then value
      when ::Symbol then value.to_s
      when ::BigDecimal then value.to_s('F')
      when ::DateTime, ::Date, ::Time then value.iso8601
      when ::Array then value.map { |element| json_value(element) }
      when ::Hash then value.transform_values { |v| json_value(v) }
      else
        value.respond_to?(:as_json) ? value.as_json : value
      end
    end

    def apply_defaults
      self.class.metadata.each do |field|
        public_send(:"#{field.name}=", field.default)
      end
    end

    def reject_unknown_attributes!(attrs)
      return if self.class.unknown_attributes == :ignore

      known = self.class.metadata.names
      unknown = attrs.keys.map(&:to_sym).reject { |k| known.include?(k) }
      return if unknown.empty?

      raise UnknownAttributeError.new(
        "unknown attribute(s) for #{self.class}: #{unknown.map(&:inspect).join(", ")}",
        keys: unknown
      )
    end

    def validate_field(field, value)
      errors.clear(field.name)
      if field.type_instance.missing?(value)
        errors.add(field.name, 'is required') if field.required?
      elsif field.options[:format]
        errors.add(field.name, 'is invalid') unless field.options[:format].match?(value)
      end
    end

    def apply_coercion_policy(field, raw_value, error)
      case self.class.coercion_policy
      when :keep_raw
        record_coercion_failure(field, raw_value, error)
        raw_value
      when :replace
        record_coercion_failure(field, nil, error)
        nil
      when :raise
        raise CoercionError.new(
          "could not coerce #{raw_value.inspect} for #{field.name}: #{error.message}",
          field_name: field.name,
          original: error
        )
      end
    end

    def record_coercion_failure(field, stored_value, error)
      instance_variable_set(:"@#{field.name}", stored_value)
      errors.clear(field.name)
      errors.add(field.name, "could not be coerced: #{error.message}")
    end
  end
end
