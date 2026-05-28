# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Boolean type. Accepts the literal +true+/+false+, the strings
    # "true"/"false" (case-insensitive), and the integers/strings 1/0.
    # Anything else raises +ArgumentError+.
    #
    # Per-field +values:+ option customizes the truthy/falsy vocabulary:
    #
    #   required :active, :boolean, values: {truthy: %w[on yes y],
    #                                        falsy:  %w[off no n]}
    #   required :flag,   :boolean, values: :english_yes_no
    #
    # Hash form takes +:truthy+ and +:falsy+ Arrays of strings (matched
    # case-insensitively). Symbol form names a built-in preset; see
    # {.presets} for the available names.
    #
    # Ruby has no Boolean class, so {#ruby_type} returns the pair
    # +[TrueClass, FalseClass]+.
    class Boolean < Base
      # @return [Array<::String>] case-insensitive strings that coerce to true
      def self.default_truthy
        %w[true 1]
      end

      # @return [Array<::String>] case-insensitive strings that coerce to false
      def self.default_falsy
        %w[false 0]
      end

      # @return [Hash{::Symbol=>Hash}] named presets for the +values:+ option
      def self.presets
        {
          english_yes_no: {truthy: %w[true yes y on 1], falsy: %w[false no n off 0]},
          english: {truthy: %w[true yes y on 1], falsy: %w[false no n off 0]},
          numeric: {truthy: %w[1], falsy: %w[0]}
        }
      end

      # Resolve a Symbol +values:+ to its preset Hash at field-declaration
      # time. Pass-through for Hash form; raises for unknown preset names.
      def self.resolve_options(options)
        return options unless options.key?(:values)

        resolved = options.dup
        if resolved[:values].is_a?(::Symbol)
          preset = presets.fetch(resolved[:values]) do
            raise ArgumentError,
              "unknown :boolean values preset #{resolved[:values].inspect}. " \
              "Available: #{presets.keys.inspect}"
          end
          resolved[:values] = preset
        end
        unless resolved[:values].is_a?(::Hash)
          raise ArgumentError, 'boolean values: must be a Hash {truthy:, falsy:} or a preset Symbol'
        end

        resolved
      end

      # @param value [Boolean, ::Integer, ::String, nil] accepts literal
      #   +true+/+false+; the integers +1+/+0+; or a String matched
      #   case-insensitively against the truthy/falsy vocabularies.
      #   Anything else raises ArgumentError.
      # @param values [Hash{::Symbol=>Array<::String>}, nil] +{truthy: [...], falsy: [...]}+
      #   custom vocabulary; +nil+ uses {.default_truthy} / {.default_falsy}
      # @return [Boolean, nil]
      # @raise [ArgumentError] when the value can't be mapped to true/false
      def coerce(value, values: nil, **)
        return nil if value.nil?
        return value if value == true || value == false # rubocop:disable Style/MultipleComparison
        return true if value == 1
        return false if value == 0

        if value.is_a?(::String)
          downcased = value.downcase
          truthy, falsy = truthy_and_falsy_for(values)
          return true if truthy.include?(downcased)
          return false if falsy.include?(downcased)
        end

        raise ArgumentError, "cannot coerce #{value.inspect} to boolean"
      end

      # @return [Array(Class, Class)] +[TrueClass, FalseClass]+
      def ruby_type
        [TrueClass, FalseClass]
      end

      private

      def truthy_and_falsy_for(values)
        return [self.class.default_truthy, self.class.default_falsy] unless values

        [
          Array(values[:truthy]).map { |s| s.to_s.downcase },
          Array(values[:falsy]).map { |s| s.to_s.downcase }
        ]
      end
    end
  end
end
