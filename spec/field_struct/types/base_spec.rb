# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Base do
  let(:type) { described_class.new }

  describe 'the coerce contract' do
    it 'raises NotImplementedError when not overridden' do
      expect { type.coerce('anything') }.to raise_error(NotImplementedError)
    end
  end

  describe 'the ruby_type contract' do
    it 'raises NotImplementedError when not overridden' do
      expect { type.ruby_type }.to raise_error(NotImplementedError)
    end
  end

  describe 'the default missing? behavior' do
    context 'when value is nil' do
      it 'is missing' do
        expect(type.missing?(nil)).to be true
      end
    end

    context 'when value is non-nil' do
      it 'is not missing' do
        expect(type.missing?('anything')).to be false
        expect(type.missing?(0)).to be false
        expect(type.missing?(false)).to be false
      end
    end
  end
end
