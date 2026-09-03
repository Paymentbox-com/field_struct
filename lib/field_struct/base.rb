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
    # Accepted values for the +coercion_policy+ macro (class- and field-level).
    VALID_COERCION_POLICIES = %i[keep_raw replace raise].freeze
    # Accepted values for the +unknown_attributes+ macro.
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

      # Mark this class (and its descendants) frozen-on-construct.
      # Instances will be Ruby-frozen at the end of {#initialize} —
      # any subsequent attempt to mutate ivars raises +FrozenError+.
      #
      # Independent of {.immutable!}. +immutable!+ blocks our setters
      # with a custom error; +frozen!+ engages Ruby's frozen-state
      # mechanism, which also locks the instance against any other
      # ivar mutation. Pick the one that matches the level of
      # strictness you need (or stack both).
      #
      # @return [true]
      def frozen!
        @frozen_on_construct = true
      end

      # @return [Boolean] whether instances of this class are frozen at
      #   the end of {#initialize} (locally or via an ancestor)
      def frozen_on_construct?
        return @frozen_on_construct if defined?(@frozen_on_construct)
        return superclass.frozen_on_construct? if superclass.respond_to?(:frozen_on_construct?)

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
      # @param value [:keep_raw, :replace, :raise] policy to set; omit to read
      # @return [:keep_raw, :replace, :raise] the resolved policy
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
      # @param value [:ignore, :raise] policy to set; omit to read
      # @return [:ignore, :raise] the resolved policy
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
      # @param name [Symbol, String] canonical field name
      # @param type_arg [Symbol, Class<Types::Base>, Class<FieldStruct::Base>]
      #   a registered name in the resolving registry, OR a +Types::Base+
      #   subclass, OR a +FieldStruct::Base+ subclass (auto-wrapped in
      #   {Types::Nested})
      # @param options [Hash{Symbol=>Object}] +required:+ (Boolean),
      #   +default:+ (literal or callable), +coercion_policy:+ (Symbol),
      #   plus type-specific options (e.g. +format:+, +round:+, +of:+,
      #   +values:+, +enum:+, +in:+) — see each type's +coerce+ for the
      #   options it consumes
      # @return [Metadata] the class-level metadata, so the DSL reads
      #   cleanly in IRB (each line prints the running set of declared
      #   fields rather than just the most recently added one). The
      #   added Field is still available as +metadata[name]+.
      def field(name, type_arg, **options)
        type_class, type_instance = resolve_type_arg(type_arg)
        if type_class <= FieldStruct::Types::Union
          type_instance, options = build_union_instance(type_class, options)
        end
        options = resolve_array_options(type_class, options)
        options = apply_default_format(type_class, options)
        options = type_class.resolve_options(options)
        validate_options!(type_class, options)
        required = options.delete(:required) { false }
        default = options.delete(:default)
        coercion_policy = options.delete(:coercion_policy)
        validate_coercion_policy_override!(coercion_policy) if coercion_policy
        description = extract_description!(options)
        field = Field.new(
          name: name, type: type_class, type_instance: type_instance,
          required: required, default: default,
          coercion_policy: coercion_policy, description: description, **options
        )
        metadata.add(field)
        define_field_accessors(field)
        metadata
      end

      # Sugar for {.field} with +required: true+.
      #
      # @param name [Symbol, String]
      # @param type_name [Symbol, Class<Types::Base>, Class<FieldStruct::Base>]
      # @param options [Hash{Symbol=>Object}]
      # @return [Metadata]
      def required(name, type_name, **options)
        field(name, type_name, **options, required: true)
      end

      # Sugar for {.field} with +required: false+ (the default).
      #
      # @param name [Symbol, String]
      # @param type_name [Symbol, Class<Types::Base>, Class<FieldStruct::Base>]
      # @param options [Hash{Symbol=>Object}]
      # @return [Metadata]
      def optional(name, type_name, **options)
        field(name, type_name, **options, required: false)
      end

      # Declare an external-name mapping for a serialization format.
      # The mapping reads internal-field-name (Symbol) on the left, the
      # external name (String) on the right; it applies to both
      # directions (import reverse-maps, export forward-maps).
      #
      #   serialize :json,
      #             first_name: 'firstName',
      #             last_name:  'lastName'
      #
      # Fields not listed in the mapping serialize under their canonical
      # name (identity). Repeating +serialize :json, ...+ on the same
      # class replaces the prior mapping (last-write-wins).
      #
      # All mapping keys must be declared fields at the moment +serialize+
      # is called — declare fields first, then declare serializations.
      # Mapping values are normalized to Strings.
      #
      # The +:json+ format ships in-gem (Phase B wires it into +to_json+ /
      # +from_json+). Future formats (CSV, XML, etc.) will be supported
      # by downstream gems reading the same metadata.
      #
      # @param name [Symbol, String] the format name (e.g. +:json+)
      # @param mapping [Hash{Symbol=>String,Symbol}] internal field name
      #   → external key. Symbol values are normalized to Strings.
      # @return [self]
      # @raise [ArgumentError] when a mapping key is not a declared field
      def serialize(name, **mapping)
        validate_serialize_mapping!(name, mapping)
        normalized = mapping.transform_values(&:to_s)
        metadata.add_serialization(name, normalized)
        self
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

      # Resolve the second positional argument of {.field}.
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

      # A human/agent-readable summary of this class's schema: the class name
      # followed by one line per field (type, required-ness, and the native
      # options that field's type accepts). A single call that answers "what
      # does this model look like, and what can I put where" without reading
      # source. See {Metadata#describe} for the field-line format.
      #
      # @return [String]
      def describe
        "#{name || "AnonymousFieldStruct"}\n#{metadata.describe}"
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

        new(canonicalize_serialized_hash(parsed))
      end

      # Walk a parsed JSON hash (string-keyed, possibly with external
      # names) and reverse-map every key to its canonical Symbol via
      # +metadata.serialization(:json)+. Recurses into nested
      # FieldStruct values and arrays of nested. Unmapped keys are
      # converted to Symbols and passed through — they'll be handled
      # by +new+'s +unknown_attributes+ check.
      #
      # @api private
      # @param hash [Hash] parsed JSON object
      # @return [Hash{Symbol=>Object}] canonical-keyed input ready for +.new+
      def canonicalize_serialized_hash(hash)
        mapping = metadata.serialization(:json)
        reverse = mapping.each_with_object({}) { |(internal, external), out| out[external] = internal }

        hash.each_with_object({}) do |(raw_key, value), result|
          canonical = reverse[raw_key.to_s] || raw_key.to_sym
          field = metadata[canonical]
          result[canonical] = canonicalize_serialized_value(value, field)
        end
      end

      # Reverse-map a single serialized value for its field, recursing into
      # nested FieldStructs and arrays of nested. Companion to
      # {.canonicalize_serialized_hash}.
      #
      # @api private
      def canonicalize_serialized_value(value, field)
        return value if field.nil?

        if value.is_a?(::Hash) && field.type <= FieldStruct::Types::Nested
          field.type_instance.struct_class.canonicalize_serialized_hash(value)
        elsif value.is_a?(::Array) && field.type <= FieldStruct::Types::Array
          of_type = field.options[:of_type]
          if of_type.is_a?(FieldStruct::Types::Nested)
            nested_class = of_type.struct_class
            value.map { |element| element.is_a?(::Hash) ? nested_class.canonicalize_serialized_hash(element) : element }
          else
            value
          end
        else
          value
        end
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

      def resolve_array_options(type_class, options)
        return options unless type_class <= FieldStruct::Types::Array
        raise ArgumentError, 'array field requires an `of:` option naming the element type' unless options.key?(:of)

        rest = options.dup
        element_class, element_instance = resolve_type_arg(rest.delete(:of))
        rest[:of_type] = element_instance || element_class
        rest
      end

      def build_union_instance(type_class, options)
        raise ArgumentError, 'union field requires an `of: [...]` option naming the member types' unless options.key?(:of)

        rest = options.dup
        members = rest.delete(:of)
        raise ArgumentError, 'union `of:` must be an Array of member types' unless members.is_a?(::Array)
        raise ArgumentError, 'union `of:` must have at least two members' if members.size < 2

        instances = members.map do |member|
          member_class, member_instance = resolve_type_arg(member)
          member_instance || member_class.new
        end
        [type_class.new(instances), rest]
      end

      def apply_default_format(type_class, options)
        return options if options.key?(:format)
        return options unless type_class.respond_to?(:default_format)

        options.merge(format: type_class.default_format)
      end

      # Pull +description:+ (canonical) or +desc:+ (alias) out of the
      # field-declaration options. Raises if both are given — pick one.
      #
      # @param options [Hash] mutated in place (keys deleted)
      # @return [String, nil]
      def extract_description!(options)
        description = options.delete(:description)
        desc = options.delete(:desc)
        if description && desc
          raise ArgumentError, 'pass either description: or desc:, not both'
        end

        description || desc
      end

      # Field options reserved by FieldStruct's own DSL on *every* field,
      # regardless of type. They're consumed by {.field} itself, so the
      # type-option check skips them.
      UNIVERSAL_FIELD_OPTIONS = %i[required default coercion_policy description desc].freeze
      private_constant :UNIVERSAL_FIELD_OPTIONS

      # Three-way option check (design invariant 7): validate native, pass
      # through foreign. For each declared option:
      #
      # 1. **Native to this type** (in its +option_schema+) → validate the
      #    value's shape against the descriptor.
      # 2. **Native to *another* registered type but not this one** → raise,
      #    naming the types it does apply to (the old "wrong family" errors,
      #    now schema-driven).
      # 3. **Not a FieldStruct option at all** → leave it untouched. Foreign
      #    options persist on the Field for downstream tooling (e.g. an Avro
      #    schema exporter).
      #
      # @param type_class [Class<Types::Base>]
      # @param options [Hash] the resolved per-field options
      # @raise [ArgumentError] on a misapplied or wrong-shaped native option
      def validate_options!(type_class, options)
        schema = type_class.option_schema
        registry = namespace_field_types || FieldStruct.types
        reserved = reserved_option_names(registry)

        options.each do |key, value|
          next if UNIVERSAL_FIELD_OPTIONS.include?(key)

          if (descriptor = schema[key])
            validate_option_value!(type_class, key, value, descriptor)
          elsif reserved.include?(key)
            raise ArgumentError, wrong_family_message(key, type_class, registry)
          end
        end
      end

      # Every option name FieldStruct treats as its own: the union of every
      # registered type's native options plus the universal field options.
      # Anything outside this set is foreign and passes through.
      #
      # @param registry [Registry]
      # @return [Array<Symbol>]
      def reserved_option_names(registry)
        native = registry.type_classes.flat_map do |type_class|
          type_class.respond_to?(:option_schema) ? type_class.option_schema.keys : []
        end
        (native + UNIVERSAL_FIELD_OPTIONS).uniq
      end

      # @raise [ArgumentError] when +value+ isn't one of the descriptor's
      #   accepted classes. +nil+ is always allowed (matches the
      #   nil-exemption of format:/enum:/in: validation).
      def validate_option_value!(type_class, key, value, descriptor)
        return if value.nil?
        return if descriptor[:type].any? { |klass| value.is_a?(klass) }

        expected = descriptor[:type].map { |klass| short_type_name(klass) }.join(' or ')
        raise ArgumentError,
          "#{key}: on #{short_type_name(type_class)} expects #{expected}, " \
          "got #{value.class} (#{value.inspect})"
      end

      # @return [String] the message for a native-elsewhere option, naming
      #   the registered types that do accept it
      def wrong_family_message(key, type_class, registry)
        accepting = registry.type_classes
          .select { |candidate| candidate.respond_to?(:option_schema) && candidate.option_schema.key?(key) }
          .map { |candidate| short_type_name(candidate) }
          .uniq
        applies = accepting.empty? ? 'no registered types' : accepting.join(', ')
        "#{key}: option does not apply to #{short_type_name(type_class)} fields. " \
          "It applies to: #{applies}."
      end

      # @return [String] the unqualified class name (+"Integer"+, not
      #   +"FieldStruct::Types::Integer"+) for readable messages
      def short_type_name(type_class)
        type_class.name.to_s.split('::').last
      end

      def validate_serialize_mapping!(name, mapping)
        unknown = mapping.keys.reject { |key| metadata[key] }
        return if unknown.empty?

        raise ArgumentError,
          "serialize :#{name} references undeclared field(s): #{unknown.map(&:inspect).join(", ")}. " \
          'Declare fields before calling serialize.'
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
            coerced = field.type_instance.coerce(value, **field.options)
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
      # @param method_names [Array<Symbol>] zero or more instance method
      #   names to invoke on each record at +valid?+ time
      # @yield [record] optional block validator
      # @yieldparam record [Base] the instance being validated
      # @return [self]
      def validate(*method_names, &block)
        method_names.each do |method_name|
          validators << ->(record) { record.public_send(method_name) }
        end
        validators << block if block
        self
      end

      # Ruby hook: give each subclass its own metadata seeded from the
      # parent's (merged copy) plus inherited macro settings, so field
      # declarations and config flow down the class chain.
      #
      # @api private
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
      freeze if self.class.frozen_on_construct?
    end

    # Bulk-update declared attributes from a hash. Routes each value
    # through the same setter pipeline used everywhere else — so coercion,
    # presence checks, and the +coercion_policy+ all run as normal.
    #
    # Respects {.unknown_attributes} on input and {.immutable?} on the
    # setter side. Keys must match declared field names. For data arriving
    # in an external naming convention, see {Base.serialize} and
    # {Base.from_json}.
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
    # @return [Hash{Symbol=>Object}] a fresh hash of current attribute values
    #   keyed by canonical field name. For format-aware export (with the
    #   declared +:json+ mapping applied), see {#as_json} / {#to_json}.
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

    # @return [Hash{Symbol=>Object}] alias of {#attributes}
    def to_h
      attributes
    end

    # @param _options [Object] unused — accepted for ActiveSupport-style symmetry
    # @return [Hash{Symbol=>Object}] a JSON-ready hash with the
    #   +:json+ serialize mapping applied. Date/Time/DateTime convert
    #   to ISO-8601 strings, BigDecimal to its plain-form string,
    #   Symbol to String. Arrays recurse. Nested FieldStructs walk
    #   through their own +as_json+, applying their own mapping.
    def as_json(_options = nil)
      mapping = self.class.metadata.serialization(:json)
      attributes.each_with_object({}) do |(field_name, value), out|
        key = mapping.key?(field_name) ? mapping[field_name].to_sym : field_name
        field = self.class.metadata[field_name]
        out[key] = json_value(value, field)
      end
    end

    # @param _options [Object] unused — accepted for ActiveSupport-style symmetry
    # @return [String] JSON representation, via Oj
    def to_json(_options = nil)
      Oj.dump(as_json, mode: :compat)
    end

    # Readable representation. Valid instances render as
    # +#<ClassName field: value, ...>+. An *invalid* instance additionally
    # surfaces its errors — +#<ClassName name: "" errors: {name: ["is
    # required"]}>+ — so the most-read debug output never hides invalidity
    # (design invariant 7). This reads the current {#errors}; it does not
    # re-run validation, so printing an instance never mutates it.
    #
    # @return [String]
    def inspect
      pairs = attributes.map { |name, value| "#{name}: #{value.inspect}" }.join(', ')
      body = "#{self.class.name || "AnonymousFieldStruct"} #{pairs}"
      current = errors.to_h
      unless current.empty?
        rendered = current.map { |field, msgs| "#{field}: #{msgs.inspect}" }.join(', ')
        body = "#{body} errors: {#{rendered}}"
      end
      "#<#{body}>"
    end

    # @return [ModelName]
    def model_name
      self.class.model_name
    end

    # @return [self] for ActiveModel-shaped helpers that call .to_model
    def to_model
      self
    end

    # Ruby pattern-matching hash protocol. Returns the declared field
    # values keyed by canonical name, sliced down to +keys+ if the
    # pattern asked for specific ones.
    #
    #   case user
    #   in { name: 'Alice', age: }
    #     ...
    #   in { name: String => name }
    #     ...
    #   end
    #
    # Nested FieldStruct values respond to the same protocol, so deep
    # patterns (+{ address: { city: 'NYC' } }+) work without extra code.
    # Aliases (per the field-name aliases feature) do *not* participate;
    # pattern matching uses canonical names, the same as Ruby-side
    # accessors.
    #
    # @param keys [Array<Symbol>, nil] keys the pattern requested, or
    #   +nil+ for the +**rest+ pattern (every declared field)
    # @return [Hash{Symbol=>Object}]
    def deconstruct_keys(keys)
      return attributes if keys.nil?

      attributes.slice(*keys)
    end

    # Ruby pattern-matching array protocol. Returns the declared field
    # values in declaration order — useful for positional unpacking of
    # small POROs whose field order is meaningful.
    #
    #   class Point < FieldStruct::Base
    #     required :x, :integer
    #     required :y, :integer
    #   end
    #
    #   case point
    #   in [x, y]
    #     Math.hypot(x, y)
    #   end
    #
    # @return [Array<Object>]
    def deconstruct
      attributes.values
    end

    private

    def json_value(value, field = nil)
      case value
      when nil, true, false, ::String, ::Integer, ::Float then value
      when ::Symbol then value.to_s
      when ::BigDecimal then value.to_s('F')
      when ::DateTime, ::Date, ::Time then temporal_json_value(value, field)
      when ::Array then value.map { |element| json_value(element, field) }
      when ::Hash then value.transform_values { |v| json_value(v, field) }
      when FieldStruct::Base then value.as_json
      else
        value.respond_to?(:as_json) ? value.as_json : value
      end
    end

    # A declared +format:+ is now stored as written, so a preset name has to be
    # expanded before strftime sees it — and only the field's own type knows
    # its preset table. With no declared format (an :array of dates, a :value
    # field holding one) the answer is ISO-8601, as it has always been.
    def temporal_json_value(value, field)
      format = field&.options&.[](:format)
      return value.iso8601 if format.nil?

      value.strftime(field.type_instance.class.resolve_format(format))
    end

    def apply_defaults
      self.class.metadata.each do |field|
        value = field.default
        value = value.call if value.respond_to?(:call)
        public_send(:"#{field.name}=", value)
      end
    end

    def run_cross_field_validators
      errors.clear(:base)
      self.class.validators.each { |validator| validator.call(self) }
    end

    def reject_unknown_attributes!(attrs)
      return if self.class.unknown_attributes == :ignore

      meta = self.class.metadata
      unknown = attrs.keys.map(&:to_sym).reject { |k| meta[k] }
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
        return
      end

      errors.add(field.name, 'is invalid') if field_value_invalid?(field, value)
    end

    def field_value_invalid?(field, value)
      fmt = field.options[:format]
      return true if fmt.is_a?(::Regexp) && !fmt.match?(value)
      return true if field.options[:enum] && !field.options[:enum].include?(value)
      return true if field.options[:in] && !within_allowed?(field.options[:in], value)

      nested_invalid?(value)
    end

    # `in:` with a Range means a BOUNDS check, so ask the Range for its bounds.
    #
    # Range#include? ENUMERATES a non-numeric range rather than comparing
    # endpoints. For a Date range that is merely wasteful — 365 successor steps
    # to answer one comparison. For a DateTime range it is wrong: the range
    # steps by whole days, so a value that isn't exactly midnight is reported
    # outside a range that plainly contains it.
    #
    #   (DateTime.new(2026, 1, 1)..DateTime.new(2026, 12, 31))
    #     .include?(DateTime.new(2026, 7, 3, 10, 30))  # => false
    #     .cover?(DateTime.new(2026, 7, 3, 10, 30))    # => true
    #
    # An Array stays a membership test. There is no string-range case to worry
    # about: the DSL refuses `in:` on String fields outright.
    def within_allowed?(allowed, value)
      allowed.is_a?(::Range) ? allowed.cover?(value) : allowed.include?(value)
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
