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

      # Declare a field. Resolves +type_arg+ — a registered symbol or a
      # {FieldStruct::Base} subclass — into a type class (and, for
      # parameterized types like {Types::Nested}, a pre-built instance),
      # builds a {Field}, adds it to the class's {Metadata}, and defines
      # the getter/setter pair.
      #
      # @param name [Symbol, String]
      # @param type_arg [Symbol, Class] a registered name OR a
      #   FieldStruct::Base subclass (auto-wrapped in {Types::Nested})
      # @param options [Hash] +required:+, +default:+, plus type-specific options
      # @return [Field] the field that was added
      def field(name, type_arg, **options)
        type_class, type_instance = resolve_type_arg(type_arg)
        resolve_array_options!(type_class, options)
        apply_default_format!(type_class, options)
        validate_format_option!(type_class, options)
        required = options.delete(:required) { false }
        default = options.delete(:default)
        aliases = Array(options.delete(:aliases))
        coercion_policy = options.delete(:coercion_policy)
        validate_coercion_policy_override!(coercion_policy) if coercion_policy
        field = Field.new(
          name: name, type: type_class, type_instance: type_instance,
          required: required, default: default, aliases: aliases,
          coercion_policy: coercion_policy, **options
        )
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

      # Resolve the second positional argument of {#field}.
      #
      # @param type_arg [Symbol, Class]
      # @return [Array(Class, Types::Base)] +[type_class, type_instance]+ —
      #   +type_instance+ is +nil+ for stock symbolic types (Field will
      #   call +type_class.new+ itself); for nested-class args (and for
      #   symbol args that resolve to a FieldStruct::Base subclass) it's
      #   a pre-built {Types::Nested} instance.
      def resolve_type_arg(type_arg)
        klass = type_arg.is_a?(::Class) ? type_arg : resolve_type(type_arg)
        if klass.is_a?(::Class) && klass < FieldStruct::Base
          [FieldStruct::Types::Nested, FieldStruct::Types::Nested.new(klass)]
        else
          [klass, nil]
        end
      end

      # @return [ModelName] an ActiveModel::Name-shaped value for this class
      def model_name
        @model_name ||= ModelName.new(name)
      end

      # Parse a JSON string and build an instance.
      #
      #   Person.from_json('{"name":"Alice","address":{"street":"1","city":"NYC"}}')
      #   # => #<Person name: "Alice", address: #<Address ...>>
      #
      # The parsed hash is fed through {#initialize} like any other input,
      # so the full setter pipeline runs: coercion (strings re-coerce to
      # Date/Time/BigDecimal), nested Hash → Types::Nested instantiation,
      # +unknown_attributes+ policy, +coercion_policy+. Invalid JSON
      # surfaces the underlying Oj parse error; a non-object root
      # (+[...]+, +"hi"+, +42+) raises +ArgumentError+.
      #
      # @param json_string [String]
      # @return [Base]
      # @raise [ArgumentError] when the parsed root is not a JSON object
      def from_json(json_string)
        parsed = Oj.load(json_string, mode: :compat)
        unless parsed.is_a?(::Hash)
          raise ArgumentError,
            "from_json expects a JSON object root, got #{parsed.class}: #{parsed.inspect}"
        end

        new(parsed)
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

        element_class, element_instance = resolve_type_arg(options.delete(:of))
        options[:of_type] = element_instance || element_class
      end

      def apply_default_format!(type_class, options)
        return if options.key?(:format)
        return unless type_class.respond_to?(:default_format)

        options[:format] = type_class.default_format
      end

      def validate_format_option!(type_class, options)
        return unless options.key?(:format)
        return if type_class <= FieldStruct::Types::String

        raise ArgumentError,
          "format: option only applies to string-shaped fields (string, immutable_string), not #{type_class}"
      end

      def validate_coercion_policy_override!(value)
        return if VALID_COERCION_POLICIES.include?(value)

        raise ArgumentError, "unknown coercion policy #{value.inspect} " \
                             "(expected one of #{VALID_COERCION_POLICIES.inspect})"
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

      public

      # @return [Array<#call>] the registered cross-field validators
      #   for this class. Each entry is a callable that takes the
      #   record. Subclasses start with a +dup+ of the parent's list at
      #   inheritance time and accumulate their own.
      def validators
        @validators ||= []
      end

      # Declare a cross-field validator.
      #
      #   class Schedule < FieldStruct::Base
      #     required :start_date, :date
      #     required :end_date,   :date
      #
      #     validate :ensure_chronological
      #     validate do |record|
      #       record.errors.add(:base, '...') if record.something_else?
      #     end
      #
      #     def ensure_chronological
      #       return unless start_date && end_date
      #
      #       errors.add(:base, 'end_date must not precede start_date') if start_date > end_date
      #     end
      #   end
      #
      # Multiple symbols can be passed in a single call. Method-symbol
      # and block forms are interchangeable — the symbol form is sugar
      # for +validate { |r| r.send(:name) }+. Validators run on every
      # call to {#valid?}, in declaration order, after per-field
      # validation.
      #
      # Per convention, validators add errors via
      # +record.errors.add(:base, '...')+ — +errors[:base]+ is cleared
      # at the start of each {#valid?} run, so prior cross-field errors
      # don't pile up. Adding to a field-specific key bypasses that
      # auto-clearing; the user is then responsible for clearing those
      # entries.
      #
      # @param method_names [Array<Symbol>] instance methods to invoke
      # @yield [record] optional block validator
      # @return [self]
      def validate(*method_names, &block)
        method_names.each do |method_name|
          validators << ->(record) { record.public_send(method_name) }
        end
        validators << block if block
        self
      end

      def inherited(subclass)
        super
        subclass.metadata.merge(metadata)
        subclass.instance_variable_set(:@validators, validators.dup)
      end
    end

    # @param attrs [Hash{Symbol,String=>Object}] input values, by symbol or string key
    def initialize(attrs = {})
      @errors = Errors.new
      apply_defaults
      assign_attributes(attrs)
      run_cross_field_validators if self.class.validators.any?
      @_initialized = true
    end

    # Bulk-update declared attributes from a hash. Routes each value
    # through the same setter pipeline used everywhere else — so coercion,
    # presence checks, and the +coercion_policy+ all run as normal.
    #
    # Respects {.unknown_attributes} on input and {.immutable?} on the
    # setter side. Honors per-field +aliases:+: an input key matching an
    # alias routes the value to the canonical field. When both canonical
    # and alias are present in the same input, the canonical wins and the
    # alias entry is ignored.
    #
    # @param attrs [Hash{Symbol,String=>Object}]
    # @return [self]
    def assign_attributes(attrs)
      reject_unknown_attributes!(attrs)
      attrs_sym = attrs.transform_keys(&:to_sym)
      attrs_sym.each do |key, value|
        field = self.class.metadata.field_for(key)
        next unless field
        # Canonical-wins: if this is an alias entry AND the canonical key
        # is also in the input, skip — the canonical entry will set it.
        next if key != field.name && attrs_sym.key?(field.name)

        public_send(:"#{field.name}=", value)
      end
      self
    end

    # @return [Hash{Symbol=>Object}] a fresh hash of current attribute values
    # @param aliased [Boolean] when true, each field's key in the output is
    #   its first declared alias (or the canonical name if no alias)
    # @return [Hash{Symbol=>Object}] a fresh hash of current attribute values
    def attributes(aliased: false)
      self.class.metadata.to_h do |field|
        key = aliased ? field.export_name : field.name
        [key, public_send(field.name)]
      end
    end

    # @return [Array<Symbol>]
    def attribute_names
      self.class.attribute_names
    end

    # @return [Errors] the per-instance error collection
    def errors
      @errors ||= Errors.new
    end

    # Run the class's cross-field validators (if any), then report
    # whether the record has any errors.
    #
    # Each call clears +errors[:base]+ before running validators, so
    # cross-field errors don't accumulate across calls. Field-level
    # errors written by setters are NOT cleared by +valid?+ — Phase 1's
    # "setter owns its field's errors" contract is preserved.
    #
    # For classes that declare no +validate+ blocks, +valid?+ stays a
    # cheap +errors.empty?+ read.
    #
    # @return [Boolean]
    def valid?
      run_cross_field_validators if self.class.validators.any?
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

    # @param aliased [Boolean] use each field's first alias for the key
    # @return [Hash{Symbol=>Object}] alias of {#attributes}
    def to_h(aliased: false)
      attributes(aliased: aliased)
    end

    # @param _options [Object] unused — accepted for ActiveSupport-style symmetry
    # @param aliased [Boolean] use each field's first alias for the key
    # @return [Hash{Symbol=>Object}] a JSON-ready hash. Date/Time/DateTime
    #   convert to ISO-8601 strings, BigDecimal to its plain-form string,
    #   Symbol to String. Arrays recurse. Nested FieldStructs walk through
    #   their own +as_json+, propagating the same +aliased:+ flag.
    def as_json(_options = nil, aliased: false)
      attributes(aliased: aliased).transform_values { |value| json_value(value, aliased: aliased) }
    end

    # @param _options [Object] unused — accepted for ActiveSupport-style symmetry
    # @param aliased [Boolean] use each field's first alias for the key
    # @return [String] JSON representation, via Oj
    def to_json(_options = nil, aliased: false)
      Oj.dump(as_json(aliased: aliased), mode: :compat)
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

    def json_value(value, aliased: false)
      case value
      when nil, true, false, ::String, ::Integer, ::Float then value
      when ::Symbol then value.to_s
      when ::BigDecimal then value.to_s('F')
      when ::DateTime, ::Date, ::Time then value.iso8601
      when ::Array then value.map { |element| json_value(element, aliased: aliased) }
      when ::Hash then value.transform_values { |v| json_value(v, aliased: aliased) }
      when FieldStruct::Base then value.as_json(aliased: aliased)
      else
        value.respond_to?(:as_json) ? value.as_json : value
      end
    end

    def apply_defaults
      self.class.metadata.each do |field|
        public_send(:"#{field.name}=", field.default)
      end
    end

    def run_cross_field_validators
      errors.clear(:base)
      self.class.validators.each { |validator| validator.call(self) }
    end

    def reject_unknown_attributes!(attrs)
      return if self.class.unknown_attributes == :ignore

      meta = self.class.metadata
      unknown = attrs.keys.map(&:to_sym).reject { |k| meta.field_for(k) }
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
      elsif nested_invalid?(value)
        errors.add(field.name, 'is invalid')
      end
    end

    def nested_invalid?(value)
      return value.invalid? if value.is_a?(FieldStruct::Base)
      return false unless value.is_a?(::Array)

      value.any? { |element| element.is_a?(FieldStruct::Base) && element.invalid? }
    end

    def apply_coercion_policy(field, raw_value, error)
      case field.coercion_policy || self.class.coercion_policy
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
