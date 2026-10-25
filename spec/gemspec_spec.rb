# frozen_string_literal: true

RSpec.describe 'the packaged gem' do
  let(:gemspec) { Gem::Specification.load(File.expand_path('../field_struct.gemspec', __dir__)) }
  let(:files) { gemspec.files }

  it 'depends on tzinfo ~> 2.0 at runtime, compatible with what ActiveSupport pins (~> 2.0, >= 2.0.5)' do
    tzinfo = gemspec.runtime_dependencies.find { |dep| dep.name == 'tzinfo' }
    expect(tzinfo.requirement).to eq(Gem::Requirement.new('~> 2.0'))
    expect(tzinfo.requirement).to be_satisfied_by(Gem::Version.new('2.0.5'))
  end

  it 'ships the library, signatures and user-facing docs' do
    expect(files).to include('lib/field_struct.rb', 'sig/field_struct.rbs', 'README.md', 'USAGE.md',
      'CHANGELOG.md', 'UPGRADING.md', 'AGENTS.md', 'docs/getting_started.md',
      'skills/field-struct/SKILL.md')
  end

  it 'is MIT-licensed and ships the license text' do
    expect(gemspec.license).to eq('MIT')
    expect(files).to include('LICENSE.txt')
  end

  it 'leaves out contributor-only files' do
    expect(files.grep(%r{\A(\.claude|CLAUDE\.md|docs/origin/|gemfiles/|benchmarks/|Rakefile|rakelib/|Steepfile|\.rubocop|\.yardopts|\.rspec|rbs_collection)}))
      .to be_empty
  end
end
