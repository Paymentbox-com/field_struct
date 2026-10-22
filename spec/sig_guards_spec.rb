# frozen_string_literal: true

require 'tmpdir'
require_relative '../rakelib/sig_guards'

# The ratchets behind `rake sigs:untyped` and the sord allowlist check in
# `sigs:generate` / `sigs:check`. See rakelib/sig_guards.rb.
RSpec.describe SigGuards do
  describe '.count_untyped' do
    it 'counts untyped tokens outside comments, across every file' do
      Dir.mktmpdir do |dir|
        a = File.join(dir, 'a.rbs')
        b = File.join(dir, 'b.rbs')
        File.write(a, <<~RBS)
          # A comment that says untyped does not count
          class A
            def x: (untyped value) -> untyped # trailing untyped comment
            attr_reader untyped_name: Integer
          end
        RBS
        File.write(b, "class B\n  def y: () -> untyped\nend\n")

        expect(described_class.count_untyped([a, b])).to eq(3)
      end
    end
  end

  describe '.untyped_failure' do
    it 'passes when the count equals the ceiling' do
      expect(described_class.untyped_failure(count: 5, ceiling: 5)).to be_nil
    end

    it 'fails when the count rises above the ceiling' do
      expect(described_class.untyped_failure(count: 6, ceiling: 5)).to match(/6 `untyped` \(ceiling 5\): 1 new/)
    end

    it 'fails when the count drops, asking for the ceiling to be lowered' do
      expect(described_class.untyped_failure(count: 4, ceiling: 5)).to match(/Lower the ceiling to 4/)
    end
  end

  describe '.sord_warnings' do
    let(:output) do
      <<~OUT
        \e[33m[OMIT ]\e[0m (FieldStruct::Field#initialize) lib/field_struct/field.rb:59: no YARD type given for "x", using untyped
        [DUCK ] (FieldStruct::Types::String#coerce) lib/field_struct/types/string.rb:25: #to_s looks like a duck type, replacing with _ToS
        [INFO ] (FieldStruct) something informational
        [OMIT ] (FieldStruct::Field#initialize) lib/field_struct/field.rb:61: no YARD type given for "x", using untyped
        [DONE ] Processed 330 objects
      OUT
    end

    it 'keeps OMIT and DUCK warnings, without colour codes or file:line, sorted and unique' do
      expect(described_class.sord_warnings(output)).to eq([
        'DUCK (FieldStruct::Types::String#coerce) #to_s looks like a duck type, replacing with _ToS',
        'OMIT (FieldStruct::Field#initialize) no YARD type given for "x", using untyped'
      ])
    end
  end

  describe '.parse_allowlist' do
    it 'drops comments and blank lines' do
      expect(described_class.parse_allowlist("# header\n\nOMIT (A#b) msg\n  \n")).to eq(['OMIT (A#b) msg'])
    end
  end

  describe '.allowlist_failure' do
    it 'passes when warnings and allowlist match exactly' do
      expect(described_class.allowlist_failure(warnings: ['OMIT (A#b) m'], allowlist: ['OMIT (A#b) m'])).to be_nil
    end

    it 'fails on a warning that is not allowlisted' do
      failure = described_class.allowlist_failure(warnings: ['OMIT (A#b) m', 'OMIT (A#c) m'], allowlist: ['OMIT (A#b) m'])
      expect(failure).to match(/1 new sord warning.*\n  OMIT \(A#c\) m/m)
    end

    it 'fails on a stale allowlist entry sord no longer emits' do
      failure = described_class.allowlist_failure(warnings: [], allowlist: ['OMIT (A#b) m'])
      expect(failure).to match(/1 allowlisted warning.*no longer emits.*\n  OMIT \(A#b\) m/m)
    end
  end

  describe 'the committed files' do
    it 'has an integer ceiling' do
      expect(File.read(described_class::UNTYPED_CEILING_FILE).strip).to match(/\A\d+\z/)
    end

    it 'has a sorted, duplicate-free allowlist' do
      entries = described_class.parse_allowlist(File.read(described_class::SORD_ALLOWLIST_FILE))
      expect(entries).to eq(entries.uniq.sort)
    end
  end
end
