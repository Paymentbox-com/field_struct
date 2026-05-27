# frozen_string_literal: true

require_relative 'string'

module FieldStruct
  module Types
    # UUID type — a {Types::String} that pre-fills the field's +format:+
    # option with a canonical RFC-4122 pattern. Bad-format input becomes
    # a Phase 1-style validation error (+"is invalid"+); coercion itself
    # still just hands back the string.
    #
    # Users can override the pattern by passing +format: /.../+ on the
    # field declaration.
    class UUID < FieldStruct::Types::String
      # Hex-digit-only canonical RFC-4122 form. Permits any version.
      #
      # @return [Regexp] applied at the field level when no +format:+ is given
      def self.default_format
        /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i
      end

      # @return [Hash{Symbol=>Regexp}] named presets for +format:+
      def self.presets
        {
          any_version: default_format,
          v4: /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/i,
          v7: /\A\h{8}-\h{4}-7\h{3}-[89ab]\h{3}-\h{12}\z/i
        }
      end

      def self.resolve_options(options)
        PresetResolver.call(options, :format, presets, label: ':uuid format')
      end
    end
  end
end
