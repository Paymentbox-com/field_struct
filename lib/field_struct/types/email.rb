# frozen_string_literal: true

require_relative 'string'

module FieldStruct
  module Types
    # Email type — a {Types::String} that pre-fills the field's +format:+
    # option with a pragmatic email pattern. Same shape as
    # {Types::UUID} / {Types::URL}: bad-format input is a validation
    # error, not a coercion failure.
    #
    # The default pattern is deliberately not RFC 5322 strict — those
    # regexes are unwieldy and reject real-world addresses. It checks
    # +local@domain.tld+ shape with no internal whitespace or extra +@+
    # characters; users can override via +format: /.../+ for stricter
    # rules.
    class Email < FieldStruct::Types::String
      DEFAULT_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      # @return [Regexp]
      def self.default_format
        DEFAULT_FORMAT
      end
    end
  end
end
