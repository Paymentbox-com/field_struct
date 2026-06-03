# frozen_string_literal: true

# The three-way field-option check: validate native, pass through foreign
# (design invariant 7, Q4). See FieldStruct::Base.validate_options!.
RSpec.describe 'field option validation' do
  describe 'foreign options pass through' do
    it 'keeps an unknown option verbatim on the Field for downstream tooling' do
      klass = Class.new(FieldStruct::Base) do
        required :id, :string, avro_namespace: 'com.acme', doc: 'the id'
      end
      options = klass.metadata[:id].options
      expect(options[:avro_namespace]).to eq('com.acme')
      expect(options[:doc]).to eq('the id')
    end

    it 'does not validate the shape of a foreign option' do
      expect do
        Class.new(FieldStruct::Base) { required :id, :string, avro_default: 12_345 }
      end.not_to raise_error
    end
  end

  describe 'native option value shape (tier 1)' do
    it 'accepts a well-shaped native value' do
      expect do
        Class.new(FieldStruct::Base) { required :price, :float, round: 2 }
      end.not_to raise_error
    end

    it 'raises when a native value is the wrong class, naming the expected shape' do
      expect do
        Class.new(FieldStruct::Base) { required :price, :float, round: '2' }
      end.to raise_error(ArgumentError, /round: on Float expects Integer, got String/)
    end

    it 'exempts nil (matching format:/enum: nil-exemption)' do
      expect do
        Class.new(FieldStruct::Base) { required :price, :float, round: nil }
      end.not_to raise_error
    end
  end

  describe 'misapplied native option (tier 2)' do
    it 'raises for a known option used on the wrong type, naming the types it applies to' do
      expect do
        Class.new(FieldStruct::Base) { required :n, :integer, round: 2 }
      end.to raise_error(ArgumentError, /round: option does not apply to Integer.*applies to: .*Float/)
    end

    it 'catches a misplaced of: on a non-array/union type' do
      expect do
        Class.new(FieldStruct::Base) { required :name, :string, of: :integer }
      end.to raise_error(ArgumentError, /of: option does not apply to String/)
    end
  end
end
