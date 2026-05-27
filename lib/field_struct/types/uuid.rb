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
      DEFAULT_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/i

      # @return [Regexp] applied at the field level when no +format:+ is given
      def self.default_format
        DEFAULT_FORMAT
      end
    end
  end
end
