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

  describe 'base: on :integer' do
    it 'parses strings in the declared base' do
      klass = Class.new(FieldStruct::Base) { field :code, :integer, base: 16 }
      instance = klass.new(code: '1A')
      expect(instance).to be_valid
      expect(instance.code).to eq(26)
    end

    it 'records a coercion error for digits outside the declared base' do
      klass = Class.new(FieldStruct::Base) { field :code, :integer, base: 16 }
      expect(klass.new(code: 'G1').errors[:code]).to include(/could not be coerced/)
    end

    it 'raises at class load when base: is not an Integer' do
      expect do
        Class.new(FieldStruct::Base) { field :code, :integer, base: '16' }
      end.to raise_error(ArgumentError, /base: on Integer expects Integer, got String/)
    end

    [1, 0, 37, -16].each do |bad|
      it "raises at class load for base: #{bad}, outside 2..36" do
        expect do
          Class.new(FieldStruct::Base) { field :code, :integer, base: bad }
        end.to raise_error(ArgumentError, /base: on Integer expects an Integer from 2 to 36/)
      end
    end

    [2, 36].each do |edge|
      it "accepts base: #{edge}" do
        expect do
          Class.new(FieldStruct::Base) { field :code, :integer, base: edge }
        end.not_to raise_error
      end
    end

    it 'is refused on a non-integer type, naming :integer' do
      expect do
        Class.new(FieldStruct::Base) { field :code, :string, base: 16 }
      end.to raise_error(ArgumentError, /base: option does not apply to String.*applies to: .*Integer/)
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
