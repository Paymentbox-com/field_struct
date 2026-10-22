# frozen_string_literal: true

require 'open3'
require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

require 'rubocop/rake_task'
require_relative 'rakelib/sig_guards'

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

# Sord exits 0 even when it can't resolve a referenced constant: it only
# logs a warning. With --replace-errors-with-untyped (no longer passed) it
# wrote +untyped+, which sigs:check couldn't see once committed; without it
# sord writes the unresolved name as-is (`rbs validate` then fails with
# NoTypeFoundError). Either way, fail here, at generation, with the fix.
#
# The usual cause is a bare stdlib name in a YARD type written inside the
# FieldStruct::Types namespace (e.g. +Symbol+ / +Array+ / +Hash+) resolving
# against +Types::Symbol+ / +Types::Array+ rather than the stdlib class.
# Fix: fully-qualify it (+::Symbol+).
def guard_sord_warnings!(output)
  plain = output.gsub(/\e\[[0-9;]*m/, '') # strip ANSI colour codes
  return unless plain.include?('important warnings in the output file')

  details = plain.lines.grep(/wasn't able to be resolved|could not be/i).map(&:strip)
  raise 'Sord could not resolve one or more YARD types — the sig would carry a ' \
        "placeholder instead of the type:\n  #{details.join("\n  ")}\n" \
        'Fix the YARD type, usually by fully-qualifying a stdlib constant ' \
        '(e.g. `::Symbol`, `::Array`, `::Hash`).'
end

# Every sord [OMIT]/[DUCK] warning must be in the committed allowlist, and
# every allowlisted warning must still occur — see rakelib/sig_guards.rb.
def guard_sord_allowlist!(output)
  allowlist = SigGuards.parse_allowlist(File.read(SigGuards::SORD_ALLOWLIST_FILE))
  failure = SigGuards.allowlist_failure(warnings: SigGuards.sord_warnings(output), allowlist: allowlist)
  raise failure if failure
end

def sord_run(target)
  # Temporarily hide the committed sig file — YARD picks up sig/*.rbs as
  # input, and the prior file's entries confuse Sord's parameter-matching
  # for kwarg-heavy methods. Move it aside, run sord, restore on failure
  # or when generating to a different target (e.g. sigs:check).
  stash = "#{SIG_FILE}.stashed-by-sord-rake"
  stashed = File.exist?(SIG_FILE) && File.rename(SIG_FILE, stash) && true
  ok = false
  cmd = "bundle exec sord #{target} --rbs --no-sord-comments --skip-constants"
  output, status = Open3.capture2e(cmd)
  puts output
  raise "sord failed (exit #{status.exitstatus})" unless status.success?

  guard_sord_warnings!(output)
  guard_sord_allowlist!(output)
  contents = File.read(target)
  SORD_FIXUPS.each { |pattern, replacement| contents.gsub!(pattern, replacement) }
  File.write(target, contents)
  ok = true
ensure
  # Only restore the stash if (a) sord failed mid-flight, or (b) the
  # caller is writing to a tmp target and we want the committed file
  # back in place. When sord succeeded and target *was* SIG_FILE, the
  # fresh output already lives at SIG_FILE — restoring would clobber it.
  restore = stashed && File.exist?(stash) && (!ok || target != SIG_FILE)
  File.rename(stash, SIG_FILE) if restore
  File.delete(stash) if stashed && File.exist?(stash) && !restore
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

  desc 'Fail unless the non-comment `untyped` count in sig/ equals the committed ceiling (ratchets down only)'
  task :untyped do
    count = SigGuards.count_untyped(Dir['sig/**/*.rbs'])
    ceiling = Integer(File.read(SigGuards::UNTYPED_CEILING_FILE).strip)
    failure = SigGuards.untyped_failure(count: count, ceiling: ceiling)
    abort failure if failure

    puts "sig/ untyped: #{count} (ceiling #{ceiling})"
  end

  desc 'Validate every sig under sig/ against the RBS grammar and resolve its names'
  task :validate do
    # The rbs collection (stdlib date/time/bigdecimal sigs) must be present
    # for the fully-qualified ::Date / ::Time / ::DateTime / ::BigDecimal
    # types in the generated sig to resolve. Install it on first run so a
    # fresh checkout's `rake release:check` is self-contained; the lock and
    # installed sigs float with the (uncommitted) Gemfile.lock.
    sh 'bundle exec rbs collection install' unless File.exist?('rbs_collection.lock.yaml')
    # The whole directory, so hand-written sigs added beside the generated
    # file are validated too.
    sh 'bundle exec rbs -I sig validate'
  end
end

# --- Documentation (yard) ---------------------------------------------

namespace :docs do
  desc 'Generate HTML API docs into doc/ from YARD comments'
  task :generate do
    # --fail-on-warning surfaces broken YARD references and malformed
    # tags so a release doesn't go out with a busted doc tree.
    sh 'bundle exec yard doc --fail-on-warning'
  end

  desc 'Show YARD coverage stats and list undocumented public methods'
  task :stats do
    sh 'bundle exec yard stats --list-undoc'
  end
end

# --- Release pre-flight -----------------------------------------------

namespace :release do
  desc 'Run the full pre-release battery: specs, rubocop, sig check, docs build'
  task check: %w[spec rubocop sigs:check sigs:validate sigs:untyped docs:generate]
end
