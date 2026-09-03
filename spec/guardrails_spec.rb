# frozen_string_literal: true

require 'shellwords'

# Guardrails that keep the spec suite self-contained, so it can't depend on
# files that aren't committed — the kind that pass locally but vanish in CI or
# a fresh clone. (Born from a spec that read a fixture out of the gitignored
# scrap/ scratch directory.)
RSpec.describe 'spec suite hygiene' do
  spec_dir = __dir__
  repo_root = File.expand_path('..', spec_dir)

  it 'no spec reads from the gitignored scrap/ directory' do
    offenders = Dir[File.join(spec_dir, '**', '*.rb')]
      .reject { |path| path == __FILE__ }
      .select { |path| File.read(path).include?('scrap') }
      .map { |path| path.delete_prefix("#{repo_root}/") }

    expect(offenders).to be_empty, <<~MSG
      These specs reference scrap/, which is gitignored — it won't exist in CI or a fresh clone:
        #{offenders.join("\n  ")}
      Put the file under spec/fixtures/ (tracked) and read it from there.
    MSG
  end

  it 'every file under spec/fixtures/ is tracked by git' do
    fixtures = File.join(spec_dir, 'fixtures')
    skip 'no spec/fixtures yet' unless Dir.exist?(fixtures)

    on_disk = Dir[File.join(fixtures, '**', '*')]
      .select { |path| File.file?(path) }
      .map { |path| path.delete_prefix("#{repo_root}/") }.sort
    tracked = `git -C #{repo_root.shellescape} ls-files spec/fixtures`.split("\n").sort

    untracked = on_disk - tracked
    expect(untracked).to be_empty, <<~MSG
      These spec fixtures exist locally but aren't committed — `git add` them or they'll be missing in CI:
        #{untracked.join("\n  ")}
    MSG
  end
end

# Framework-independence guardrail.
#
# FieldStruct must behave identically whether or not ActiveSupport is loaded.
# The way that broke, three times over, was always the same: `lib/` dispatched
# on a `respond_to?` probe against a USER VALUE, and ActiveSupport defines
# exactly those methods on core classes. `''.respond_to?(:to_date)` is false on
# plain Ruby and true under Rails, so the gem silently ran different code in the
# two worlds and its own suite could only ever see one of them.
#
# The rule: never dispatch on a predicate a framework can redefine. Dispatch on
# the stdlib class methods we name explicitly — Date.parse, Time.parse,
# strptime — which ActiveSupport does not redefine.
#
# This runs in milliseconds and catches a new probe at PR time. It does NOT
# replace the ActiveSupport lane: AS changes semantics (String#to_time returning
# nil, Time.=== matching a TimeWithZone, Date.parse's comp flag), not just which
# predicates answer true. A probe-free `lib/` is necessary, not sufficient.
RSpec.describe 'framework-independence guardrails' do
  repo_root = File.expand_path('..', __dir__)

  # Methods ActiveSupport (or another framework) adds to or redefines on core
  # classes. A `respond_to?` check against any of these answers differently
  # depending on what the host loaded, which is the whole problem.
  framework_predicates = %w[
    to_date to_time to_datetime as_json blank? present? presence try
    in_time_zone acts_like? to_fs to_formatted_s deep_dup
  ].freeze
  probe_pattern = /respond_to\?\(:(#{Regexp.union(framework_predicates)})\)/

  # The one deliberate exception, kept and documented rather than removed.
  #
  # `Base#json_value`'s terminal arm is reached only for :value-typed fields —
  # every temporal and scalar value is handled by an explicit `when` above it.
  # There, the ActiveSupport outcome is the BETTER one: a Struct serializes as
  # {"x":1,"y":2} under AS versus the string "#<struct ...>" on plain Ruby. This
  # is an integration, not an accident, and it is specced in both lanes.
  allowed_probes = {
    'lib/field_struct/base.rb' => %w[as_json]
  }.freeze

  it 'no code in lib/ dispatches on a framework-redefinable predicate' do
    offenders = Dir[File.join(repo_root, 'lib', '**', '*.rb')].flat_map do |path|
      relative = path.delete_prefix("#{repo_root}/")
      allowed = allowed_probes.fetch(relative, [])

      File.readlines(path).each_with_index.filter_map do |line, index|
        next if line.strip.start_with?('#') # prose about the rule, not a probe

        match = line.match(probe_pattern)
        next if match.nil? || allowed.include?(match[1])

        "#{relative}:#{index + 1} — respond_to?(:#{match[1]})"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      These sites dispatch on a predicate ActiveSupport defines or redefines on core
      classes, so they take a different branch under Rails than they do in this suite:

        #{offenders.join("\n  ")}

      Dispatch on an explicit stdlib class instead (`case value when ::String ...`)
      and parse through a class method ActiveSupport does not redefine — Date.parse,
      Time.parse, DateTime.parse, strptime. If the probe is genuinely wanted, add it
      to `allowed_probes` with a comment saying why, and spec it in BOTH lanes.
    MSG
  end

  # The guard is worthless if the pattern silently stops matching. Prove it
  # still fires on the exact shape it exists to catch.
  it 'actually detects the shape it is looking for' do
    expect('return value.to_date if value.respond_to?(:to_date)').to match(probe_pattern)
    expect('value.respond_to?(:call) ? value.call : value').not_to match(probe_pattern)
  end
end
