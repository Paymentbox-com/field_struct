# frozen_string_literal: true

# The per-type native-option descriptors that back option validation and
# discoverability (design invariant 7). See FieldStruct::Types::Base.option_schema.
RSpec.describe 'Types option_schema' do
  describe FieldStruct::Types::Base do
    it 'has no native options by default' do
      expect(described_class.option_schema).to eq({})
    end

    it 'normalizes a descriptor via .option' do
      expect(described_class.option(type: Integer)).to eq(
        type: [Integer], required: false, presets: []
      )
    end

    it 'freezes the descriptor and its sub-arrays' do
      descriptor = described_class.option(type: [Array, Range], presets: %i[a b])
      expect(descriptor).to be_frozen
      expect(descriptor[:type]).to be_frozen
      expect(descriptor[:presets]).to be_frozen
    end
  end

  describe 'merging and memoization' do
    it 'merges own_option_schema down the class chain' do
      # UUID adds nothing of its own beyond format; enum comes from String.
      expect(FieldStruct::Types::UUID.own_option_schema.keys).to eq([:format])
      expect(FieldStruct::Types::UUID.option_schema.keys).to contain_exactly(:format, :enum)
    end

    it 'returns a frozen, memoized result (computed once per type)' do
      first = FieldStruct::Types::Integer.option_schema
      expect(first).to be_frozen
      expect(FieldStruct::Types::Integer.option_schema).to equal(first)
    end
  end

  describe FieldStruct::Types::String do
    it 'accepts format: (Regexp/Symbol) and enum: (Array)' do
      schema = described_class.option_schema
      expect(schema.keys).to contain_exactly(:format, :enum)
      expect(schema[:format][:type]).to contain_exactly(Regexp, Symbol)
      expect(schema[:enum][:type]).to eq([Array])
      expect(schema[:format][:required]).to be false
    end
  end

  describe FieldStruct::Types::ImmutableString do
    it 'inherits String options unchanged' do
      expect(described_class.option_schema).to eq(FieldStruct::Types::String.option_schema)
    end
  end

  describe FieldStruct::Types::Integer do
    it 'accepts only in:' do
      expect(described_class.option_schema.keys).to eq([:in])
      expect(described_class.option_schema[:in][:type]).to contain_exactly(Array, Range)
    end
  end

  describe FieldStruct::Types::Float do
    it 'accepts round: (Integer) and in:' do
      expect(described_class.option_schema.keys).to contain_exactly(:round, :in)
      expect(described_class.option_schema[:round][:type]).to eq([Integer])
    end
  end

  describe FieldStruct::Types::Boolean do
    it 'accepts values: with the preset names advertised' do
      values = described_class.option_schema.fetch(:values)
      expect(values[:type]).to contain_exactly(Hash, Symbol)
      expect(values[:presets]).to include(:english_yes_no, :numeric)
    end
  end

  describe FieldStruct::Types::Date do
    it 'accepts format: (String/Symbol with presets) and in:' do
      schema = described_class.option_schema
      expect(schema.keys).to contain_exactly(:format, :in)
      expect(schema[:format][:type]).to contain_exactly(String, Symbol)
      expect(schema[:format][:presets]).to include(:iso8601, :us, :eu)
    end
  end

  describe FieldStruct::Types::Symbol do
    it 'accepts only enum:' do
      expect(described_class.option_schema.keys).to eq([:enum])
    end
  end

  describe FieldStruct::Types::UUID do
    it 'inherits String format/enum and advertises its format presets' do
      schema = described_class.option_schema
      expect(schema.keys).to contain_exactly(:format, :enum)
      expect(schema[:format][:presets]).to include(:v4, :v7)
    end
  end

  describe FieldStruct::Types::Array do
    it 'requires of: (Symbol or Class)' do
      of = described_class.option_schema.fetch(:of)
      expect(of[:required]).to be true
      expect(of[:type]).to contain_exactly(Symbol, Class)
    end
  end

  describe FieldStruct::Types::Union do
    it 'requires of: as an Array' do
      of = described_class.option_schema.fetch(:of)
      expect(of[:required]).to be true
      expect(of[:type]).to eq([Array])
    end
  end
end
