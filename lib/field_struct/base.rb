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
    class << self
      # @return [Metadata] the per-class field collection (memoized)
      def metadata
        @metadata ||= Metadata.new
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

      def define_field_accessors(field)
        attr_reader field.name

        define_method(:"#{field.name}=") do |value|
          coerced = field.type_instance.coerce(value, field.options)
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
      self.class.metadata.each do |field|
        value = attrs.fetch(field.name) { attrs.fetch(field.name.to_s) { field.default } }
        public_send(:"#{field.name}=", value)
      end
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

    private

    def validate_field(field, value)
      errors.clear(field.name)
      errors.add(field.name, 'is required') if field.required? && field.type_instance.missing?(value)
    end
  end
end
