# frozen_string_literal: true

require_relative 'field_struct/version'
require_relative 'field_struct/types/base'
require_relative 'field_struct/types/string'
require_relative 'field_struct/types/immutable_string'
require_relative 'field_struct/types/integer'
require_relative 'field_struct/types/float'

module FieldStruct
  class Error < StandardError; end
end
