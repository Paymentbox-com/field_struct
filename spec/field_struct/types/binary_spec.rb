# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Binary do
  let(:type) { described_class.new }

  describe 'coercing input' do
    it 'returns nil for nil input' do
      expect(type.coerce(nil)).to be_nil
    end

    it 'returns a String with ASCII-8BIT encoding for any non-nil input' do
      result = type.coerce('hello')
      expect(result).to eq('hello'.b)
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'preserves raw byte content (no whitespace stripping)' do
      bytes = "\x00\x01\x02\xFF".b
      expect(type.coerce(bytes)).to eq(bytes)
    end

    it 'works on Symbol input via super#to_s + force_encoding' do
      result = type.coerce(:abc)
      expect(result).to eq('abc')
      expect(result.encoding).to eq(Encoding::ASCII_8BIT)
    end

    it 'returns a new object (does not mutate the source)' do
      utf8 = 'café'
      coerced = type.coerce(utf8)
      expect(utf8.encoding).to eq(Encoding::UTF_8) # source unchanged
      expect(coerced.encoding).to eq(Encoding::ASCII_8BIT)
    end
  end

  describe 'reporting missing values' do
    it 'is missing for nil' do
      expect(type.missing?(nil)).to be true
    end

    it 'is missing for an empty string' do
      expect(type.missing?('')).to be true
    end

    it 'is NOT missing for whitespace bytes (unlike :string)' do
      expect(type.missing?("\n")).to be false
      expect(type.missing?(' ')).to be false
      expect(type.missing?("\x00")).to be false
    end

    it 'is not missing for populated bytes' do
      expect(type.missing?("\x00\x01\x02".b)).to be false
    end
  end

  describe 'reporting ruby_type' do
    it 'returns the top-level String class' do
      expect(type.ruby_type).to eq(String)
    end
  end

  describe 'integration via the DSL' do
    let(:klass) do
      Class.new(FieldStruct::Base) { required :payload, :binary }
    end

    it 'is registered as :binary on the base registry' do
      expect(klass.new(payload: 'data').payload).to eq('data'.b)
    end

    it 'reports "is required" for nil' do
      expect(klass.new(payload: nil).errors[:payload]).to include('is required')
    end

    it 'reports "is required" for empty string' do
      expect(klass.new(payload: '').errors[:payload]).to include('is required')
    end

    it 'accepts whitespace bytes as present (the key difference from :string)' do
      expect(klass.new(payload: "\n  \t")).to be_valid
    end
  end
end
