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
    end

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
    def each(&block)
      @fields.each_value(&block)
    end

    # Copy fields from +parent+ into self, leaving already-declared names
    # untouched (child wins). Order: existing self fields stay where they
    # are; parent fields are appended in iteration order if not present.
    #
    # @param parent [Metadata]
    # @return [self]
    def merge(parent)
      parent.each do |field|
        @fields[field.name] = field unless @fields.key?(field.name)
      end
      self
    end
  end
end
