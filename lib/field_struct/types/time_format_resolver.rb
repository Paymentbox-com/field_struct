# frozen_string_literal: true

module FieldStruct
  module Types
    # Shared +format:+ option resolution for {Date}/{Time}/{DateTime}.
    # Each of those types calls +TimeFormatResolver.call(options, presets)+
    # from its +resolve_options+ class method.
    #
    # A declared +format:+ is VALIDATED at declaration time and kept exactly as
    # the user wrote it; it is resolved to a strftime string later, at coerce
    # and render time, by {.resolve}.
    #
    # Keeping the declaration is the point. The Symbol used to be overwritten
    # with the strftime String it expands to, which destroyed the only fact a
    # documentation generator actually wants — that the field is +:iso8601+,
    # not some anonymous String of percent-escapes. Recovering the name by
    # reverse-mapping the String worked only while no two presets shared a
    # value, which is luck rather than a contract.
    module TimeFormatResolver
      # Validate a declared +format:+ and return the options unchanged.
      #
      # @param options [::Hash{::Symbol => Object}] the per-field options as written
      # @param presets [::Hash{::Symbol => ::String}] the type's preset table
      # @return [::Hash{::Symbol => Object}] +options+, unmodified
      # @raise [ArgumentError] when +format:+ is the wrong shape, or names a
      #   preset the type does not have — at declaration time, not at first use
      def self.call(options, presets)
        return options unless options.key?(:format)

        fmt = options[:format]
        return options if fmt.is_a?(::String) || fmt.is_a?(::Regexp) || fmt.nil?
        raise ArgumentError, "format: must be a String, Regexp, or Symbol — got #{fmt.class}" unless fmt.is_a?(::Symbol)

        resolve(fmt, presets) # raises on an unknown name; the result is discarded
        options
      end

      # Resolve a declared +format:+ to a strftime/strptime String.
      #
      # @param format [::String, ::Symbol, nil] as declared
      # @param presets [::Hash{::Symbol => ::String}] the type's preset table
      # @return [::String, nil] +nil+ when no format is declared
      # @raise [ArgumentError] when the Symbol names no preset in the table
      def self.resolve(format, presets)
        return format if format.nil? || format.is_a?(::String)

        presets.fetch(format) do
          raise ArgumentError,
            "unknown time format preset #{format.inspect}. Available: #{presets.keys.inspect}"
        end
      end
    end
  end
end
