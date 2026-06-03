# frozen_string_literal: true

module FieldStruct
  module Types
    # Abstract base for all FieldStruct type classes.
    #
    # Subclasses must implement {#coerce} and {#ruby_type}. They may override
    # {#missing?} when their notion of "missing" is broader than nil-only
    # (e.g. strings consider empty/whitespace missing, arrays consider empty
    # missing).
    class Base
      # Native per-field options this type understands, as a frozen Hash of
      # option-name (Symbol) → descriptor. Each descriptor is built by
      # {.option} and carries the accepted value classes, whether the option
      # is required at declaration time, and any Symbol presets it accepts.
      #
      # The empty default means "no native options." Subclasses override with
      # +super.merge(...)+ so a subtype inherits its parent's options — e.g.
      # {Types::UUID} inherits {Types::String}'s +format:+ / +enum:+ for free.
      #
      # This is the single source of truth for both *validation* (the DSL
      # checks declared values against these descriptors) and *discoverability*
      # (an agent or human can ask a type what it accepts without reading
      # source). Options *not* listed here are treated as foreign and pass
      # through onto the Field untouched, available to downstream tooling.
      #
      # @return [Hash{Symbol=>Hash}]
      def self.option_schema
        {}
      end

      # Build a normalized descriptor for {.option_schema}.
      #
      # @param type [Class, Array<Class>] the Ruby class(es) a declared value
      #   may be an instance of
      # @param required [Boolean] whether the option must be present at
      #   field-declaration time
      # @param presets [Array<Symbol>] Symbol preset names the option also accepts
      # @return [Hash] a frozen descriptor: +{ type:, required:, presets: }+
      def self.option(type:, required: false, presets: [])
        {type: ::Kernel.Array(type).freeze, required: required, presets: presets.to_a.freeze}.freeze
      end

      # Resolve symbolic preset references on the per-field options hash
      # at field-declaration time. Default implementation passes options
      # through unchanged; concrete types override to interpret their
      # own options (e.g. +format: :iso8601+ → strftime string).
      #
      # @param options [Hash] the per-field options hash, as written by the user
      # @return [Hash] possibly-modified options to store on the Field
      def self.resolve_options(options)
        options
      end

      # Coerce an input value into the type's domain.
      #
      # The contract here is intentionally loose — subclasses override with
      # explicit kwargs for the options they consume (e.g. +format:+ for
      # Date, +round:+ for Float, +of_type:+ for Array), plus a trailing
      # +**+ catch-all so a call site that splats +field.options+ can pass
      # keys that some types ignore. See each subclass's +coerce+ for the
      # exact accepted options.
      #
      # @param value [Object] raw input — each subclass narrows this to
      #   the inputs it actually accepts
      # @return [Object] the coerced value
      # @raise [NotImplementedError] always, unless overridden by a subclass
      def coerce(value, **)
        raise NotImplementedError, "#{self.class} must implement #coerce"
      end

      # Whether the given value should be treated as "missing" for the purpose
      # of presence checks. The default is nil-only; subclasses override for
      # emptier notions.
      #
      # @param value [Object]
      # @return [Boolean]
      def missing?(value)
        value.nil?
      end

      # The native Ruby class a coerced value will be an instance of.
      # Used by the (deferred) RBS generator and for introspection.
      #
      # @return [Class]
      # @raise [NotImplementedError] always, unless overridden by a subclass
      def ruby_type
        raise NotImplementedError, "#{self.class} must implement #ruby_type"
      end

      # Concise type-instance representation. The default shows just the
      # type-class name (e.g. +#<FieldStruct::Types::String>+). Subclasses
      # that carry parameter state (Nested, Union, …) override to surface
      # what they wrap.
      #
      # @return [::String]
      def inspect
        full = self.class.name || 'AnonymousType'
        prefixed = full.sub(/\AFieldStruct\b/, FieldStruct.inspect_namespace)
        "#<#{prefixed}>"
      end

      # @param pp [Object] a PP-shaped sink (responds to +#text+)
      # @return [void]
      def pretty_print(pp)
        pp.text(inspect)
      end
    end
  end
end
