# frozen_string_literal: true

require_relative 'base'

module FieldStruct
  module Types
    # Value type. A no-coercion passthrough — whatever you give it comes
    # back unchanged. Useful as an escape hatch when you want a field
    # declaration to participate in metadata without committing to a
    # specific shape.
    class Value < Base
      # @param value [Object] raw input
      # @return [Object] the value, unchanged
      def coerce(value, **)
        value
      end

      # @return [Class] +Object+ — the broadest sensible class
      def ruby_type
        ::Object
      end
    end
  end
end
