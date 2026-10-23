# frozen_string_literal: true

# Drift guard for UPGRADING.md. Convention (see CLAUDE.md "Documentation"):
#
# - Every top-level CHANGELOG bullet under a "### ...Breaking..." heading, in
#   [Unreleased] and every version >= 0.11.0, ends its first line with an
#   invisible `<!-- upgrading: some-slug -->` marker.
# - UPGRADING.md carries the same marker under the entry that explains it.
#   Any other CHANGELOG bullet (a visible Changed or Fixed item) may opt in
#   with a marker, and is then held to the same rule.
# - Every top-level bullet under a "### Changed" or "### Removed" heading in
#   [Unreleased] records a decision: a slug marker (held to the rule above)
#   or `<!-- upgrading: none -->`, the author's "no caller action". `none` is
#   not a slug and never satisfies a Breaking bullet. Released sections are
#   not retro-checked.
# - UPGRADING.md declares the range it covers in
#   `<!-- upgrading-range: FROM..TO -->`; TO must reach the gem's VERSION.
#
# The slug is the key, not the bullet's wording, so either file can be
# reworded freely without breaking the link.
module UpgradingGuide
  MARKER = /<!--\s*upgrading:\s*(?!none\s*-->)([a-z0-9][a-z0-9-]*)\s*-->/
  NONE = /<!--\s*upgrading:\s*none\s*-->/
  DECIDED = /\A###\s+(?:Changed|Removed)\b/i
  RANGE = /<!--\s*upgrading-range:\s*(\d+\.\d+\.\d+)\.\.(\d+\.\d+\.\d+)\s*-->/
  FIRST_GUARDED = Gem::Version.new('0.11.0')

  module_function

  # CHANGELOG sections ([Unreleased] and versions >= FIRST_GUARDED) as
  # { "0.13.0" => lines }.
  def guarded_sections(changelog)
    sections = {}
    current = nil
    changelog.each_line do |line|
      if (m = line.match(/\A## \[([^\]]+)\]/))
        guarded = m[1] == 'Unreleased' || Gem::Version.new(m[1]) >= FIRST_GUARDED
        current = guarded ? m[1] : nil
        sections[current] = [] if current
      elsif current
        sections[current] << line
      end
    end
    sections
  end

  # Top-level bullets (with their continuation lines) under a Breaking heading.
  def breaking_bullets(lines) = bullets_under(lines, /\A### .*breaking/i).map(&:last)

  # Top-level bullets (with their continuation lines) under a heading that
  # matches +heading+, as [heading, bullet] pairs.
  def bullets_under(lines, heading)
    bullets = []
    current = nil
    lines.each do |line|
      if line.start_with?('### ')
        current = line.match?(heading) ? line.strip : nil
      elsif current && line.start_with?('- ')
        bullets << [current, +line]
      elsif current && bullets.any? && !line.strip.empty?
        bullets.last.last << line
      end
    end
    bullets
  end

  # Human-readable problems; empty when the guide is in sync.
  def problems(changelog:, upgrading:, version:)
    found = []
    markers = []
    guarded_sections(changelog).each do |name, lines|
      breaking_bullets(lines).each do |bullet|
        next if bullet.match?(MARKER)

        found << "CHANGELOG [#{name}] Breaking bullet has no `<!-- upgrading: slug -->` marker: " \
                 "#{bullet.lines.first.strip[0, 90]}"
      end
      if name == 'Unreleased'
        bullets_under(lines, DECIDED).each do |heading, bullet|
          next if bullet.match?(MARKER) || bullet.match?(NONE)

          found << "CHANGELOG [Unreleased] #{heading} bullet needs `<!-- upgrading: slug -->` (with an " \
                   "UPGRADING.md entry) or `<!-- upgrading: none -->`: #{bullet.lines.first.strip[0, 90]}"
        end
      end
      markers.concat(lines.join.scan(MARKER).flatten.map { |slug| [name, slug] })
    end

    covered = upgrading.scan(MARKER).flatten
    markers.each do |name, slug|
      next if covered.include?(slug)

      found << "CHANGELOG [#{name}] marks `#{slug}` but UPGRADING.md has no `<!-- upgrading: #{slug} -->` entry"
    end

    range = upgrading.match(RANGE)
    if range.nil?
      found << 'UPGRADING.md has no `<!-- upgrading-range: FROM..TO -->` marker'
    elsif Gem::Version.new(range[2]) < Gem::Version.new(version)
      found << "UPGRADING.md covers up to #{range[2]} but the gem is #{version}: add a section " \
               '(even "no changes") and raise the range'
    end
    found
  end

  # GitHub's heading anchor: lowercase, drop punctuation except - and _,
  # spaces to hyphens.
  def slug(heading)
    heading.strip.downcase.gsub(/[^\p{Word}\- ]/, '').tr(' ', '-')
  end

  # Anchors of every Markdown heading outside fenced code.
  def anchors(markdown)
    fenced = false
    markdown.each_line.filter_map do |line|
      fenced = !fenced if line.lstrip.start_with?('```')
      next if fenced

      (m = line.match(/\A#+ (.+)/)) && slug(m[1])
    end
  end
end

RSpec.describe 'UPGRADING.md' do
  def read(path) = File.read(File.expand_path("../#{path}", __dir__))

  let(:changelog) { read('CHANGELOG.md') }
  let(:upgrading) { read('UPGRADING.md') }

  it 'has an entry for every Breaking CHANGELOG bullet since 0.11.0 and covers the current version' do
    expect(UpgradingGuide.problems(changelog: changelog, upgrading: upgrading, version: FieldStruct::VERSION))
      .to eq([])
  end

  it 'links only to anchors that exist in itself and in USAGE.md' do
    own = UpgradingGuide.anchors(upgrading)
    usage = UpgradingGuide.anchors(read('USAGE.md'))
    broken_own = upgrading.scan(/\]\(#([^)]+)\)/).flatten.reject { |a| own.include?(a) }
    broken_usage = upgrading.scan(/\]\(USAGE\.md#([^)]+)\)/).flatten.reject { |a| usage.include?(a) }
    expect(broken_own + broken_usage.map { |a| "USAGE.md##{a}" }).to eq([])
  end

  describe 'the guard itself' do
    let(:problems) do
      lambda do |**overrides|
        args = {changelog: changelog, upgrading: upgrading, version: FieldStruct::VERSION}.merge(overrides)
        UpgradingGuide.problems(**args)
      end
    end

    it 'fails when an UPGRADING.md entry is deleted' do
      expect(problems.call(upgrading: upgrading.sub('<!-- upgrading: float-refuses-hex -->', '')))
        .to include(a_string_including('`float-refuses-hex`'))
    end

    it 'fails when a Breaking bullet has no marker' do
      bullet = "## [Unreleased]\n\n### Breaking-ish (visible behaviour changes)\n\n- **Something new.** Details.\n\n"
      expect(problems.call(changelog: changelog.sub("## [Unreleased]\n", bullet)))
        .to include(a_string_including('[Unreleased] Breaking bullet has no'))
    end

    # A fixture, not the live files: [Unreleased] is often empty.
    describe 'every [Unreleased] Changed / Removed bullet records a decision' do
      let(:changelog) do
        <<~MD
          ## [Unreleased]

          ## [0.20.0] - 2026-01-01

          ### Changed

          - **Old.** Released history is not retro-checked.

          ### Breaking-ish (visible behaviour changes)

          - **Alpha.** Details. <!-- upgrading: alpha -->
        MD
      end
      let(:upgrading) { "<!-- upgrading-range: 0.10.0..0.20.0 -->\n\n### Alpha\n<!-- upgrading: alpha -->\n" }

      def unreleased(heading, bullet)
        problems.call(changelog: changelog.sub("## [Unreleased]\n", "## [Unreleased]\n\n#{heading}\n\n#{bullet}\n"),
          version: '0.20.0')
      end

      it 'passes the fixture as it stands' do
        expect(problems.call(version: '0.20.0')).to eq([])
      end

      it 'fails on an unmarked bullet under Changed or Removed' do
        ['### Changed', '### Removed'].each do |heading|
          expect(unreleased(heading, "- **Renamed.** `a` is now `b`.\n  More detail."))
            .to eq(["CHANGELOG [Unreleased] #{heading} bullet needs `<!-- upgrading: slug -->` (with an " \
                    'UPGRADING.md entry) or `<!-- upgrading: none -->`: - **Renamed.** `a` is now `b`.'])
        end
      end

      it 'passes a bullet marked `none`, with no guide entry' do
        expect(unreleased('### Changed', "- **Faster.** No caller action.\n  <!-- upgrading: none -->")).to eq([])
      end

      it 'fails a slug with no guide entry' do
        expect(unreleased('### Removed', '- **Gone.** `c` is removed. <!-- upgrading: gone-c -->'))
          .to eq(['CHANGELOG [Unreleased] marks `gone-c` but UPGRADING.md has no `<!-- upgrading: gone-c -->` entry'])
      end

      it 'does not let `none` stand in for a Breaking bullet\'s slug' do
        expect(unreleased('### Breaking-ish (visible behaviour changes)', '- **X.** Details. <!-- upgrading: none -->'))
          .to include(a_string_including('[Unreleased] Breaking bullet has no'))
      end

      it 'leaves other headings alone' do
        expect(unreleased('### Added', '- **New.** A method.')).to eq([])
      end
    end

    it 'fails when the version moves past the covered range' do
      covered = upgrading[UpgradingGuide::RANGE, 2]
      bumped = Gem::Version.new(covered).bump.to_s.then { |v| "#{v}.0" } # 0.13.0 -> 0.14.0
      expect(problems.call(version: bumped)).to include(a_string_including("covers up to #{covered} but the gem is #{bumped}"))
    end
  end
end
