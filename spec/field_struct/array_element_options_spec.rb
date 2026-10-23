# frozen_string_literal: true

require 'bigdecimal'

# `element:` passes the element type's own options to every element of an
# :array field — the options a scalar field of that type would take.
RSpec.describe 'array element: options' do
  def struct(&block)
    Class.new(FieldStruct::Base, &block)
  end

  describe 'coercing each element with the element options' do
    it 'reads each string in the declared base' do
      klass = struct { optional :ids, :array, of: :integer, element: {base: 16} }
      expect(klass.new(ids: %w[ff 10]).ids).to eq([255, 16])
    end

    it 'refuses a non-integral element under strict: true' do
      klass = struct { optional :ids, :array, of: :integer, element: {strict: true} }
      record = klass.new(ids: [1, 2.0, 3.5])
      expect(record.errors[:ids]).to eq(
        ['could not be coerced: element at index 2: Integer fields with strict: true expect a whole number, ' \
         'got a Float that is not one']
      )
    end

    it 'rounds each element' do
      klass = struct { optional :prices, :array, of: :decimal, element: {round: 2} }
      expect(klass.new(prices: ['1.005', '2.999']).prices).to eq([BigDecimal('1.01'), BigDecimal('3.0')])
    end

    it 'parses each element with a declared format' do
      klass = struct { optional :days, :array, of: :date, element: {format: :us} }
      expect(klass.new(days: ['10/22/2026']).days).to eq([Date.new(2026, 10, 22)])
    end

    it 'reads each zone-less element at the declared zone' do
      klass = struct { optional :at, :array, of: :time, element: {zone: '-06:00'} }
      expect(klass.new(at: ['2026-10-22 10:00:00']).at.first.utc_offset).to eq(-6 * 3600)
    end

    it 'reads each element with a values: vocabulary' do
      klass = struct { optional :flags, :array, of: :boolean, element: {values: :english} }
      expect(klass.new(flags: %w[yes no]).flags).to eq([true, false])
    end

    it 'leaves elements coerced by default when no element: is declared' do
      klass = struct { optional :ids, :array, of: :integer }
      expect(klass.new(ids: [3.5]).ids).to eq([3])
    end

    it 'leaves nil elements alone' do
      klass = struct { optional :ids, :array, of: :integer, element: {strict: true, in: 1..3} }
      record = klass.new(ids: [1, nil])
      expect(record.ids).to eq([1, nil])
      expect(record).to be_valid
    end
  end

  describe 'validating each element with the element options' do
    it 'names the index of every element outside in:' do
      klass = struct { optional :ids, :array, of: :integer, element: {in: 1..10} }
      record = klass.new(ids: [1, 5, 11, 12])
      expect(record.errors[:ids]).to eq(['elements at index 2, 3 are invalid'])
      expect(record.errors.full_messages).to eq(['Ids elements at index 2, 3 are invalid'])
    end

    it 'checks a Regexp format: on each string element' do
      klass = struct { optional :codes, :array, of: :string, element: {format: /\A[A-Z]{3}\z/} }
      expect(klass.new(codes: %w[USD EUR]).errors[:codes]).to be_empty
      expect(klass.new(codes: %w[USD eur]).errors[:codes]).to eq(['element at index 1 is invalid'])
    end

    it 'checks a preset format: on each element' do
      klass = struct { optional :ids, :array, of: :uuid, element: {format: :v4} }
      expect(klass.new(ids: ['00000000-0000-1000-8000-000000000000']).errors[:ids])
        .to eq(['element at index 0 is invalid'])
    end

    it 'checks enum: on each element' do
      klass = struct { optional :currencies, :array, of: :string, element: {enum: %w[USD EUR]} }
      expect(klass.new(currencies: %w[EUR GBP]).errors[:currencies]).to eq(['element at index 1 is invalid'])
    end

    it 'keeps array-level presence rules unchanged' do
      klass = struct { required :ids, :array, of: :integer, element: {in: 1..10} }
      expect(klass.new(ids: []).errors[:ids]).to eq(['is required'])
    end
  end

  describe 'error messages name the index and never the value' do
    it 'prefixes an element coercion failure with its index, for any array' do
      klass = struct { optional :ids, :array, of: :integer }
      expect(klass.new(ids: %w[1 SENTINEL-4111]).errors[:ids]).to eq(
        ['could not be coerced: element at index 1: Integer fields expect a base-10 integer, ' \
         'got a String that is not one']
      )
    end

    it 'carries the index into a CoercionError under :raise' do
      klass = struct { optional :ids, :array, of: :integer, element: {base: 16}, coercion_policy: :raise }
      expect { klass.new(ids: %w[ff zz-4111]) }.to raise_error(
        FieldStruct::CoercionError,
        'could not coerce Array input for ids: element at index 1: Integer fields expect a base-16 integer, ' \
        'got a String that is not one'
      )
    end

    it 'keeps the element error class' do
      expect do
        FieldStruct::Types::Array.new.coerce([1, {a: 1}], of_type: FieldStruct::Types::String, element: {strict: true})
      end.to raise_error(TypeError, /\Aelement at index 1: /)
    end
  end

  describe 'declaration-time validation with the element type schema' do
    it 'refuses a wrong-shaped element option, naming the field and element' do
      expect { struct { optional :ids, :array, of: :integer, element: {base: '16'} } }.to raise_error(
        ArgumentError, 'in element: of array field :ids, base: on Integer expects Integer, got String ("16")'
      )
    end

    it "refuses a value the element type's own resolver refuses" do
      expect { struct { optional :ids, :array, of: :integer, element: {base: 99} } }.to raise_error(
        ArgumentError, 'in element: of array field :ids, base: on Integer expects an Integer from 2 to 36, got 99'
      )
    end

    it 'refuses an unknown preset' do
      expect { struct { optional :days, :array, of: :date, element: {format: :nope} } }
        .to raise_error(ArgumentError, /\Ain element: of array field :days, unknown .*preset :nope/)
    end

    it 'refuses an invalid zone' do
      expect { struct { optional :at, :array, of: :time, element: {zone: 'Mars/Olympus_Mons'} } }
        .to raise_error(ArgumentError, /\Ain element: of array field :at, zone:/)
    end

    it 'refuses an option the element type does not accept, listing what it does' do
      expect { struct { optional :ids, :array, of: :integer, element: {round: 2} } }.to raise_error(
        ArgumentError,
        'in element: of array field :ids, round: is not an Integer option. Integer accepts: in, base, strict.'
      )
    end

    it 'refuses a field-level option inside element:' do
      expect { struct { optional :ids, :array, of: :integer, element: {required: true} } }.to raise_error(
        ArgumentError,
        'in element: of array field :ids, required: is a field option, not an element option. ' \
        'Declare it on the field itself.'
      )
    end

    it 'says a nested element type takes no options' do
      address = struct { optional :city, :string }
      expect { struct { optional :homes, :array, of: address, element: {strict: true} } }.to raise_error(
        ArgumentError, /\Ain element: of array field :homes, strict: is not a Nested option. Nested accepts no options\.\z/
      )
    end

    it 'refuses element: when the element type is itself an array' do
      expect { struct { optional :grid, :array, of: :array, element: {of: :integer} } }.to raise_error(
        ArgumentError, /\Ain element: of array field :grid, element options are not supported for Array elements/
      )
    end

    it 'refuses a non-Hash element:' do
      expect { struct { optional :ids, :array, of: :integer, element: :strict } }.to raise_error(
        ArgumentError, 'element: on Array expects Hash, got Symbol (:strict)'
      )
    end

    it 'refuses element: on a non-array field, naming the type it applies to' do
      expect { struct { optional :id, :integer, element: {strict: true} } }.to raise_error(
        ArgumentError, 'element: option does not apply to Integer fields. It applies to: Array.'
      )
    end
  end

  describe 'introspection' do
    let(:klass) do
      struct { optional :ids, :array, of: :integer, element: {strict: true, base: 16} }
    end

    it 'shows the element options in Metadata#to_h' do
      expect(klass.metadata.to_h[:ids][:options]).to eq(of_type: 'Integer', element: {strict: true, base: 16})
    end

    it 'shows the element options in describe' do
      expect(klass.describe).to include('ids (Array, optional) — of_type: Integer, element: {strict: true, base: 16}')
    end

    it 'lists what the element type accepts in describe, by name only' do
      # The shapes are the element type's own (Types::Integer.option_schema);
      # repeating them made every array line twice as long.
      expect(klass.describe).to include('— element accepts in, base, strict')
      expect(klass.describe).not_to include('element accepts in (')
    end

    it 'shows the element options in Field#inspect' do
      expect(klass.metadata[:ids].inspect).to include('element={strict: true, base: 16}')
    end

    it 'freezes the stored element options' do
      expect(klass.metadata[:ids].options[:element]).to be_frozen
    end

    it 'keeps the RBS element type (no element option changes the Ruby class)' do
      expect(FieldStruct::RBS.type_for(klass.metadata[:ids])).to eq('::Array[::Integer?]?')
    end

    it 'stores no element: key when none is declared' do
      plain = struct { optional :ids, :array, of: :integer }
      expect(plain.metadata[:ids].options).not_to have_key(:element)
    end
  end

  describe 'JSON round trip' do
    it 'writes each temporal element in its declared format, so from_json reads it back' do
      klass = struct { optional :days, :array, of: :date, element: {format: '%d/%m/%Y'} }
      record = klass.new(days: ['22/10/2026'])
      expect(record.to_json).to eq('{"days":["22/10/2026"]}')
      expect(klass.from_json(record.to_json)).to eq(record)
    end
  end
end
