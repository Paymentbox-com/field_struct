# frozen_string_literal: true

# An array error names EVERY bad index, not only the first: with dozens of
# elements, fixing one at a time and resubmitting is the failure mode. One bad
# element reads as before; several list their indexes (the first five, then a
# count), and the reason shown is the first one's. Values are never echoed.
RSpec.describe 'array errors name every bad index' do
  def struct(&block)
    Class.new(FieldStruct::Base, &block)
  end

  let(:ints) { struct { optional :ids, :array, of: :integer } }
  let(:reason) { 'Integer fields expect a base-10 integer, got a String that is not one' }

  describe 'coercion' do
    it 'keeps the single-element message unchanged' do
      expect(ints.new(ids: [1, 'x', 3]).errors[:ids]).to eq(["could not be coerced: element at index 1: #{reason}"])
    end

    it 'lists every refused index, showing the first reason' do
      expect(ints.new(ids: [1, 'x', 3, 'y', {a: 1}]).errors[:ids])
        .to eq(["could not be coerced: elements at index 1, 3, 4 (index 1 shown): #{reason}"])
    end

    it 'lists the first five and counts the rest' do
      ids = Array.new(12) { |i| i.even? ? 'x' : i }
      expect(ints.new(ids: ids).errors[:ids])
        .to eq(["could not be coerced: elements at index 0, 2, 4, 6, 8 and 1 more (index 0 shown): #{reason}"])
      expect(ints.new(ids: Array.new(20, 'x')).errors[:ids].first)
        .to start_with('could not be coerced: elements at index 0, 1, 2, 3, 4 and 15 more (index 0 shown): ')
    end

    it 'keeps the first error class and its cause' do
      type = FieldStruct::Types::Array.new
      expect { type.coerce([1, {a: 1}, 'x'], of_type: FieldStruct::Types::Integer) }
        .to raise_error(TypeError, /\Aelements at index 1, 2 \(index 1 shown\): /)
    end

    it 'says the same under coercion_policy :raise' do
      klass = struct do
        coercion_policy :raise
        optional :ids, :array, of: :integer
      end
      expect { klass.new(ids: ['x', 2, 'y']) }.to raise_error(
        FieldStruct::CoercionError,
        "could not coerce Array input for ids: elements at index 0, 2 (index 0 shown): #{reason}"
      )
    end
  end

  describe 'element validation' do
    let(:klass) { struct { optional :ids, :array, of: :integer, element: {in: 1..9} } }

    it 'keeps the single-element message unchanged' do
      expect(klass.new(ids: [1, 20, 3]).errors[:ids]).to eq(['element at index 1 is invalid'])
    end

    it 'lists every invalid index' do
      expect(klass.new(ids: [1, 20, nil, 30, 4, 0]).errors[:ids]).to eq(['elements at index 1, 3, 5 are invalid'])
      expect(klass.new(ids: [1, 20, nil, 30, 4, 0]).errors.full_messages).to eq(['Ids elements at index 1, 3, 5 are invalid'])
    end

    it 'lists the first five and counts the rest' do
      expect(klass.new(ids: Array.new(8, 0)).errors[:ids]).to eq(['elements at index 0, 1, 2, 3, 4 and 3 more are invalid'])
    end
  end
end
