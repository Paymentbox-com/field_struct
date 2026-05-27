# frozen_string_literal: true

module FieldStruct
  module Types
    # Generic preset resolution for a single named option on a single
    # type. Symbol values are looked up in the supplied presets hash;
    # anything else passes through. Unknown preset names raise
    # +ArgumentError+ at field-declaration time.
    #
    # Used by string-shaped types (Email/UUID/URL) for +format:+ and by
    # time-shaped types (Date/Time/DateTime) via {TimeFormatResolver}
    # (which adds a stricter set of allowed value types).
    module PresetResolver
      def self.call(options, key, presets, label:)
        return options unless options.key?(key)

        value = options[key]
        return options unless value.is_a?(::Symbol)

        resolved = presets.fetch(value) do
          raise ArgumentError,
            "unknown #{label} preset #{value.inspect}. Available: #{presets.keys.inspect}"
        end
        options.merge(key => resolved)
      end
    end
  end
end
