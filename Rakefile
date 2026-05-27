# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'

RuboCop::RakeTask.new

task default: %i[spec rubocop]

# --- Type signatures (sord + rbs) -------------------------------------

SIG_FILE = 'sig/field_struct.rbs'

# Sord limitations that need a tiny post-process pass.
#
# Each entry is [search_regex, replacement]. Keep this list short and
# document each entry — if it grows, it's a smell that we should fix
# YARD upstream or open an issue against Sord.
SORD_FIXUPS = [
  # Sord emits +include Enumerable+ untyped; RBS requires the type param.
  # The only Enumerable in this gem is Metadata, which iterates Field.
  [/^    include Enumerable$/, '    include ::Enumerable[Field]']
].freeze

def sord_run(target)
  # Temporarily hide the committed sig file — YARD picks up sig/*.rbs as
  # input, and the prior file's entries confuse Sord's parameter-matching
  # for kwarg-heavy methods. Move it aside, run sord, restore.
  stash = "#{SIG_FILE}.stashed-by-sord-rake"
  stashed = File.exist?(SIG_FILE) && File.rename(SIG_FILE, stash) && true
  sh "bundle exec sord #{target} --rbs --no-sord-comments --skip-constants --replace-errors-with-untyped"
  contents = File.read(target)
  SORD_FIXUPS.each { |pattern, replacement| contents.gsub!(pattern, replacement) }
  File.write(target, contents)
ensure
  File.rename(stash, SIG_FILE) if stashed && File.exist?(stash)
end

namespace :sigs do
  desc 'Regenerate sig/field_struct.rbs from YARD comments via sord'
  task :generate do
    sord_run(SIG_FILE)
  end

  desc 'Check that the committed sig file matches a fresh sord run (CI guard)'
  task :check do
    require 'tmpdir'
    require 'digest'
    Dir.mktmpdir do |dir|
      tmp = File.join(dir, 'field_struct.rbs')
      sord_run(tmp)
      committed = Digest::SHA256.file(SIG_FILE).hexdigest
      generated = Digest::SHA256.file(tmp).hexdigest
      next if committed == generated

      warn "::: #{SIG_FILE} is stale. Run `rake sigs:generate` and commit the result."
      sh "diff -u #{SIG_FILE} #{tmp} || true"
      exit 1
    end
  end

  desc 'Validate sig/field_struct.rbs against the RBS grammar'
  task :validate do
    sh "bundle exec rbs --no-collection -I #{SIG_FILE} validate"
  end
end
