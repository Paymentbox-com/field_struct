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
