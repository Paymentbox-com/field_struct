# frozen_string_literal: true

# Report-only (see gemfiles/types.gemfile): `steep check` here measures how far
# the YARD-generated sig/ is from type-checking lib/. Nothing gates on it yet.

# Stdlib sigs come from the library line below; the rbs collection (and its
# lock, derived from the main Gemfile.lock) is for `rake sigs:validate`.
disable_collection

target :lib do
  signature 'sig'
  check 'lib'

  # Stdlib the gem requires directly. Oj ships no sigs, so its calls report as
  # unknown constants — part of the count until a sig-private/ stub lands.
  library 'date', 'time', 'bigdecimal'
end
