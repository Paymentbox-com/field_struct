# frozen_string_literal: true

require_relative 'string'

module FieldStruct
  module Types
    # URL type — a {Types::String} that pre-fills the field's +format:+
    # option with a practical http(s) URL pattern. Same shape as
    # {Types::UUID}: bad-format input is a Phase 1 validation error,
    # not a coercion failure.
    #
    # The default pattern matches +http://+ and +https://+ URLs with a
    # non-empty host. It is intentionally pragmatic, not RFC 3986
    # exhaustive — users can override via +format: /.../+ if they need
    # different schemes or stricter host rules.
    class URL < FieldStruct::Types::String
      DEFAULT_FORMAT = %r{\Ahttps?://[^\s/$.?#][^\s]*\z}i

      # @return [Regexp]
      def self.default_format
        DEFAULT_FORMAT
      end
    end
  end
end
