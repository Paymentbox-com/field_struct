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
  end
end
