# frozen_string_literal: true

module FieldStruct
  module Types
    # Shared +format:+ option resolution for {Date}/{Time}/{DateTime}.
    # Each of those types calls +TimeFormatResolver.call(options, presets)+
    # from its +resolve_options+ class method.
    #
    # Symbol +format:+ values are looked up in the type's presets table;
    # String values pass through. Anything else raises ArgumentError.
    module TimeFormatResolver
      def self.call(options, presets)
        return options unless options.key?(:format)

        fmt = options[:format]
        return options if fmt.is_a?(::String) || fmt.is_a?(::Regexp) || fmt.nil?
        raise ArgumentError, "format: must be a String, Regexp, or Symbol — got #{fmt.class}" unless fmt.is_a?(::Symbol)

        resolved = presets.fetch(fmt) do
          raise ArgumentError,
            "unknown time format preset #{fmt.inspect}. Available: #{presets.keys.inspect}"
        end
        options.merge(format: resolved)
      end
    end
  end
end
