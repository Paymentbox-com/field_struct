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
      # @param value [Object] raw input
      # @param options [Hash] type-specific parameters (e.g. +:of_type+ for arrays)
      # @return [Object] the coerced value
      # @raise [NotImplementedError] always, unless overridden by a subclass
      def coerce(value, options = {})
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
    end
  end
end
