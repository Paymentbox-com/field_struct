# frozen_string_literal: true

module FieldStruct
  # The per-class collection of {Field} declarations.
  #
  # Mutable while a class is being defined — the DSL adds fields as it
  # encounters them — and queried thereafter by name or via iteration.
  # Subclass inheritance is handled by {#merge}: a fresh child Metadata
  # is seeded with the parent's fields, then accumulates its own; child
  # declarations win on conflict.
  class Metadata
    include Enumerable

    def initialize
      @fields = {}
      @serializations = {}
    end

    # @return [Hash{Symbol=>Hash{Symbol=>String}}] declared
    #   external-name mappings keyed by format name. Each inner hash
    #   maps an internal field name (Symbol) to its external name
    #   (String). Fields not listed in an inner hash serialize under
    #   their canonical name.
    attr_reader :serializations

    # @param field [Field]
    # @return [self]
    def add(field)
      @fields[field.name] = field
      self
    end

    # @param name [Symbol, String]
    # @return [Field, nil]
    def [](name)
      @fields[name.to_sym]
    end

    # @return [Array<Symbol>] field names in insertion order
    def names
      @fields.keys
    end

    # Yields each {Field} in insertion order.
    #
    # @yield [field]
    # @yieldparam field [Field]
    # @return [Enumerator] when no block is given
    def each(&block)
      @fields.each_value(&block)
    end

    # A copy-pasteable schema view of the declared fields, keyed by field
    # name. Each value is a plain Hash of primitives/strings (no live type
    # objects), so the result reads cleanly in a console and is safe to
    # `pp` or dump — handy for seeing a model's shape without reading its
    # source. Option values that are classes or type instances are rendered
    # as short names; a callable default shows as +"<callable>"+.
    #
    #   User.metadata.to_h
    #   # => { name: { type: "String", ruby_type: "String", required: true,
    #   #              default: nil, options: {}, description: nil }, ... }
    #
    # When a block is given this falls back to +Enumerable#to_h+ (mapping
    # each {Field} to a pair), preserving existing callers.
    #
    # @return [Hash{Symbol=>Hash{Symbol=>Object}}] field name → schema, or
    #   the block-mapped pairs when a block is supplied
    def to_h(&block)
      return super if block

      @fields.transform_values { |field| field_schema(field) }
    end

    # Record a serialization mapping for the named format. Repeats on
    # the same format name replace the prior mapping (last-write-wins).
    # The mapping is frozen on its way in.
    #
    # @param name [Symbol, String]
    # @param mapping [Hash{Symbol=>String}]
    # @return [self]
    def add_serialization(name, mapping)
      @serializations[name.to_sym] = mapping.freeze
      self
    end

    # Look up the mapping for a format. Returns an empty hash when the
    # format hasn't been declared — the implicit identity mapping that
    # serializers fall back to.
    #
    # @param name [Symbol, String]
    # @return [Hash{Symbol=>String}] frozen mapping (empty hash when undeclared)
    def serialization(name)
      @serializations[name.to_sym] || EMPTY_SERIALIZATION
    end

    EMPTY_SERIALIZATION = {}.freeze
    private_constant :EMPTY_SERIALIZATION

    # Copy fields and serializations from +parent+ into self, leaving
    # already-declared entries untouched (child wins). Order: existing
    # self fields stay where they are; parent fields are appended in
    # iteration order if not present.
    #
    # @param parent [Metadata]
    # @return [self]
    def merge(parent)
      parent.each do |field|
        @fields[field.name] = field unless @fields.key?(field.name)
      end
      parent.serializations.each do |name, mapping|
        @serializations[name] = mapping unless @serializations.key?(name)
      end
      self
    end

    # Concise one-line representation. Lists the declared field names
    # and, when present, the declared serialization formats — without
    # dumping the underlying ivar hashes.
    #
    # @return [String]
    def inspect
      return "#<#{FieldStruct.inspect_namespace}::Metadata empty>" if @fields.empty?

      parts = ["fields=#{@fields.keys.inspect}"]
      parts << "serializations=#{@serializations.keys.inspect}" unless @serializations.empty?
      "#<#{FieldStruct.inspect_namespace}::Metadata #{parts.join(" ")}>"
    end

    # Multi-line representation suitable for IRB / pp. Renders each
    # field on its own indented line using {Field#inspect}, with the
    # closing +>+ on its own line.
    #
    # @param pp [Object] a PP-shaped sink (responds to +#text+)
    # @return [void]
    def pretty_print(pp)
      if @fields.empty?
        pp.text(inspect)
        return
      end

      pp.text("#<#{FieldStruct.inspect_namespace}::Metadata")
      @fields.each_value do |field|
        pp.text("\n  ")
        pp.text(field.inspect)
      end
      pp.text("\n  serializations=#{@serializations.keys.inspect}") unless @serializations.empty?
      pp.text("\n>")
    end

    private

    # Render one field as a primitive-only schema Hash for {#to_h}.
    def field_schema(field)
      {
        type: short_name(field.type),
        ruby_type: ruby_type_repr(field.type_instance.ruby_type),
        required: field.required?,
        default: schema_value(field.default),
        options: field.options.transform_values { |value| schema_value(value) },
        description: field.description
      }
    end

    # A single class, or +A | B+ for a multi-class ruby_type (boolean, union).
    def ruby_type_repr(ruby_type)
      Array(ruby_type).map(&:name).join(' | ')
    end

    # Reduce an option/default value to something printable: short class
    # names for type references, +"<callable>"+ for procs, recursion into
    # Array/Hash, everything else as-is.
    def schema_value(value)
      case value
      when nil, true, false, ::Numeric, ::String, ::Symbol, ::Regexp, ::Range then value
      when ::Class then short_name(value)
      when FieldStruct::Types::Base then short_name(value.class)
      when ::Array then value.map { |element| schema_value(element) }
      when ::Hash then value.transform_values { |element| schema_value(element) }
      else
        value.respond_to?(:call) ? '<callable>' : value
      end
    end

    def short_name(klass)
      klass.name.to_s.split('::').last
    end
  end
end
