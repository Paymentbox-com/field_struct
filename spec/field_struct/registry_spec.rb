# frozen_string_literal: true

RSpec.describe FieldStruct::Registry do
  describe 'an empty registry' do
    let(:registry) { described_class.new }

    it 'has no parent' do
      expect(registry.parent).to be_nil
    end

    it 'reports key? false for any name' do
      expect(registry.key?(:string)).to be false
    end

    it 'raises KeyError on lookup' do
      expect { registry.lookup(:string) }.to raise_error(KeyError)
    end
  end

  describe 'registering a type' do
    let(:registry) { described_class.new }

    before { registry.register(:string, FieldStruct::Types::String) }

    it 'resolves the registered name via lookup' do
      expect(registry.lookup(:string)).to eq(FieldStruct::Types::String)
    end

    it 'reports key? true for the registered name' do
      expect(registry.key?(:string)).to be true
    end

    it 'accepts string-form names and normalizes to symbol' do
      registry.register('integer', FieldStruct::Types::Integer)
      expect(registry.lookup(:integer)).to eq(FieldStruct::Types::Integer)
      expect(registry.lookup('integer')).to eq(FieldStruct::Types::Integer)
    end

    it 'allows a later registration to overwrite an earlier one' do
      replacement = Class.new(FieldStruct::Types::Base)
      registry.register(:string, replacement)
      expect(registry.lookup(:string)).to eq(replacement)
    end
  end

  describe 'registering an alias' do
    let(:registry) { described_class.new }

    before do
      registry.register(:big_decimal, FieldStruct::Types::BigDecimal)
      registry.register(:decimal, :big_decimal)
    end

    it 'resolves the alias to the target type class' do
      expect(registry.lookup(:decimal)).to eq(FieldStruct::Types::BigDecimal)
    end

    context 'when the target is not registered' do
      it 'raises KeyError at alias-registration time' do
        expect { registry.register(:money, :not_a_real_type) }.to raise_error(KeyError)
      end
    end
  end

  describe 'parent-chain lookup' do
    let(:parent) do
      described_class.new.tap { |r| r.register(:string, FieldStruct::Types::String) }
    end
    let(:child) { described_class.new(parent) }

    it 'exposes the parent via #parent' do
      expect(child.parent).to equal(parent)
    end

    it 'looks up names not in the child registry from the parent' do
      expect(child.lookup(:string)).to eq(FieldStruct::Types::String)
    end

    it 'reports key? true for names inherited from the parent' do
      expect(child.key?(:string)).to be true
    end

    context 'when the child shadows a parent name' do
      it 'returns the child registration, not the parent' do
        shadow = Class.new(FieldStruct::Types::Base)
        child.register(:string, shadow)
        expect(child.lookup(:string)).to eq(shadow)
        expect(parent.lookup(:string)).to eq(FieldStruct::Types::String)
      end
    end

    context 'when the name is not registered anywhere' do
      it 'raises KeyError' do
        expect { child.lookup(:not_there) }.to raise_error(KeyError)
      end
    end
  end
end

RSpec.describe 'FieldStruct.types base registry' do
  it 'is a Registry instance' do
    expect(FieldStruct.types).to be_a(FieldStruct::Registry)
  end

  it 'has no parent' do
    expect(FieldStruct.types.parent).to be_nil
  end

  it 'memoizes a single instance' do
    expect(FieldStruct.types).to equal(FieldStruct.types)
  end

  it 'resolves each scalar type by its registered name' do
    expect(FieldStruct.types.lookup(:string)).to eq(FieldStruct::Types::String)
    expect(FieldStruct.types.lookup(:immutable_string)).to eq(FieldStruct::Types::ImmutableString)
    expect(FieldStruct.types.lookup(:integer)).to eq(FieldStruct::Types::Integer)
    expect(FieldStruct.types.lookup(:float)).to eq(FieldStruct::Types::Float)
    expect(FieldStruct.types.lookup(:big_decimal)).to eq(FieldStruct::Types::BigDecimal)
    expect(FieldStruct.types.lookup(:boolean)).to eq(FieldStruct::Types::Boolean)
    expect(FieldStruct.types.lookup(:date)).to eq(FieldStruct::Types::Date)
    expect(FieldStruct.types.lookup(:time)).to eq(FieldStruct::Types::Time)
    expect(FieldStruct.types.lookup(:datetime)).to eq(FieldStruct::Types::DateTime)
    expect(FieldStruct.types.lookup(:value)).to eq(FieldStruct::Types::Value)
  end

  it 'exposes :decimal as an alias for :big_decimal' do
    expect(FieldStruct.types.lookup(:decimal)).to eq(FieldStruct::Types::BigDecimal)
  end
end
