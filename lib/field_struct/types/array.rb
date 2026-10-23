# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Array type. Coerces each element through the registered element
    # type named by the +:of+ DSL option (resolved at field-declaration
    # time and stashed as +options[:of_type]+ — a class, not a symbol).
    #
    # An optional +:element+ Hash carries the element type's own options
    # (+strict:+, +base:+, +format:+, …), passed to every element's coerce:
    #
    #   optional :ids, :array, of: :integer, element: {strict: true, base: 16}
    #
    # A refused element is reported with its index — +element at index 2: …+ —
    # and several with all of theirs (see {.elements_at}).
    #
    # Missing: +nil+ or empty array. ruby_type: +::Array+.
    class Array < Base
      # Native options: a required +of:+ naming the element type — a
      # registered Symbol or a Class (a +Types::Base+ or +FieldStruct::Base+
      # subclass) — and an +element:+ Hash of that element type's options.
      #
      # @return [::Hash{::Symbol => ::Hash{::Symbol => Object}}]
      def self.own_option_schema
        {
          of: option(type: [::Symbol, ::Class], required: true),
          element: option(type: [::Hash])
        }
      end

      # The element type class behind an +of_type+ option, whether it holds
      # a class (+:integer+ → {Types::Integer}) or a built instance (a
      # {Types::Nested}). Its +option_schema+ is what +element:+ accepts.
      #
      # @param of_type [Class, Types::Base] an array field's +:of_type+ option
      # @return [Class<Types::Base>] a {Types::Base} subclass
      def self.element_class(of_type)
        of_type.is_a?(::Class) ? of_type : of_type.class
      end

      # @param value [::Array<Object, nil>, nil] anything else raises TypeError
      # @param of_type [Class, Types::Base, nil] the element type — a
      #   Types::Base subclass for stock types, or an already-built
      #   instance for parameterized types like {Types::Nested}. The DSL
      #   stashes this when the user writes +of: :string+ / +of: SomeStruct+.
      #   Required at the type level; nil here means the type was called
      #   directly without DSL help.
      # @param element [::Hash{::Symbol => Object, nil}, nil] the element
      #   type's options, passed to every element's coerce (the DSL's
      #   +element:+, already validated against the element type's schema)
      # @return [::Array<Object, nil>, nil] each element coerced by +of_type+
      # @raise [TypeError] when input is non-nil and not an Array
      # @raise [ArgumentError] when +of_type+ is missing
      # @raise [StandardError] whatever the element type raises on a bad
      #   element; an ArgumentError, TypeError or RangeError keeps its class
      #   and gains an +element at index N: + prefix — or, when several
      #   elements are refused, +elements at index N, M (index N shown): +
      def coerce(value, of_type: nil, element: nil, **)
        return nil if value.nil?
        raise ::TypeError, "expected Array, got #{value.class}" unless value.is_a?(::Array)
        raise ArgumentError, 'array coerce requires of_type:' if of_type.nil?

        element_type = element_type_for(of_type)
        # A manual index and no empty **splat keep this hot loop as cheap as it
        # was before element options (each_with_index.map + **{} cost ~40%).
        index = -1
        value.map do |item|
          index += 1
          element ? element_type.coerce(item, **element) : element_type.coerce(item)
        rescue ArgumentError, ::TypeError, ::RangeError => e
          # Off the hot loop: only a refused array pays for finding the rest.
          raise_refused!(value, index, e, element_type, element)
        end
      end

      # How many indexes an element error lists before counting the rest.
      # @return [::Integer]
      INDEXES_LISTED = 5

      # Name a set of element indexes for an error message: one reads
      # +element at index 2+, several +elements at index 2, 5+, and past
      # {INDEXES_LISTED} the rest are counted (+… and 7 more+). Indexes only,
      # never elements, so a message carries no value.
      #
      # @param indexes [::Array<::Integer>] ascending, at least one
      # @return [::String]
      def self.elements_at(indexes)
        return "element at index #{indexes.first}" if indexes.size == 1

        listed = indexes.first(INDEXES_LISTED).join(', ')
        rest = indexes.size - INDEXES_LISTED
        rest.positive? ? "elements at index #{listed} and #{rest} more" : "elements at index #{listed}"
      end

      # @param value [Object]
      # @return [Boolean] +true+ when +nil+ or empty
      def missing?(value)
        return true if value.nil?
        return true if value.respond_to?(:empty?) && value.empty?

        false
      end

      # @return [Class] the top-level +::Array+ class
      def ruby_type
        ::Array
      end

      private

      # Coerce the elements after the first refused one, so the error names
      # every refused index, then raise the first element's error with them.
      # The same message reaches every coercion_policy, :raise included —
      # finishing the scan costs a refused array no more than an accepted one.
      #
      # @param value [::Array<Object, nil>] the input array
      # @param first [::Integer] the index of the first refused element
      # @param error [StandardError] what the element type raised for it
      # @param element_type [Types::Base] the element type instance
      # @param element [::Hash{::Symbol => Object, nil}, nil] element options
      # @return [void]
      # @raise [StandardError] +error+'s class, prefixed with the indexes
      def raise_refused!(value, first, error, element_type, element)
        indexes = [first]
        (first + 1).upto(value.size - 1) do |index|
          item = value[index]
          element ? element_type.coerce(item, **element) : element_type.coerce(item)
        rescue ArgumentError, ::TypeError, ::RangeError
          indexes << index
        end
        shown = indexes.size == 1 ? '' : " (index #{first} shown)"
        # Exception#exception keeps the class without calling a custom
        # initializer; the indexes, never the elements, are added. The cause
        # chain stays what it was, rather than gaining the unprefixed copy.
        raise error.exception("#{self.class.elements_at(indexes)}#{shown}: #{error.message}"), cause: error.cause
      end

      # +of_type+ may be either a Types::Base subclass (the DSL form for
      # stock types like +:string+) or an already-built Types::Base
      # instance (the DSL form for parameterized types like
      # {Types::Nested}). Both produce a single cached instance per
      # configured element type.
      #
      # @param type_or_instance [Class<Types::Base>, Types::Base]
      # @return [Types::Base]
      def element_type_for(type_or_instance)
        return type_or_instance unless type_or_instance.is_a?(::Class)

        @element_type_instances ||= {}
        @element_type_instances[type_or_instance] ||= type_or_instance.new
      end
    end
  end
end
