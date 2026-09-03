# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/spec/'
    enable_coverage :branch
  end
end

# The ActiveSupport lane (gemfiles/activesupport-*.gemfile) loads AS *before*
# FieldStruct, so the suite runs against a host that has already monkey-patched
# the core classes — String#to_date, Time.===, Date#to_time and the rest. That
# is the environment the gem's own suite could never see, and the one in which
# v0.9.0 failed 7 examples.
#
# Deprecations are raised rather than warned. That is not tidiness: under AS 7.2
# `DateTime#to_time` emits a deprecation, so any code reaching for it fails the
# lane loudly instead of quietly returning the wrong zone.
if ENV['FIELD_STRUCT_ACTIVESUPPORT']
  require 'active_support/all'
  ActiveSupport.deprecator.behavior = :raise
end

require 'field_struct'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
