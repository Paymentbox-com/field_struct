# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'enum: and in: field options' do
  describe 'enum: on string-like fields' do
    context 'with a :string field' do
      let(:klass) do
        Class.new(described_class) do
          required :status, :string, enum: %w[on off]
        end
      end

      it 'accepts a value from the enum list' do
        expect(klass.new(status: 'on')).to be_valid
      end

      it 'records "is invalid" for a value outside the enum list' do
        expect(klass.new(status: 'maybe').errors[:status]).to include('is invalid')
      end

      it 'coerces the value first, then checks membership' do
        # :string coerces :on to 'on' through to_s
        expect(klass.new(status: :on)).to be_valid
      end
    end

    context 'with a :symbol field' do
      let(:klass) do
        Class.new(described_class) do
          required :position, :symbol, enum: %i[before after]
        end
      end

      it 'accepts a value from the enum list' do
        expect(klass.new(position: :before)).to be_valid
      end

      it 'coerces strings to symbols before checking' do
        expect(klass.new(position: 'after')).to be_valid
      end

      it 'records "is invalid" for an unlisted value' do
        expect(klass.new(position: :elsewhere).errors[:position]).to include('is invalid')
      end
    end

    context 'on a non-string-like type' do
      it 'raises ArgumentError at class load' do
        expect do
          Class.new(described_class) { required :n, :integer, enum: [1, 2, 3] }
        end.to raise_error(ArgumentError, /enum: option does not apply to Integer/)
      end
    end

    context 'with a non-Array value' do
      it 'raises ArgumentError at class load' do
        expect do
          Class.new(described_class) { required :s, :string, enum: 'on' }
        end.to raise_error(ArgumentError, /Array/)
      end
    end
  end

  describe 'in: on rangy fields' do
    context 'with an Array on an :integer field' do
      let(:klass) do
        Class.new(described_class) do
          required :page_size, :integer, in: [10, 20, 30]
        end
      end

      it 'accepts a listed value' do
        expect(klass.new(page_size: 20)).to be_valid
      end

      it 'coerces a string first, then checks membership' do
        expect(klass.new(page_size: '10')).to be_valid
      end

      it 'records "is invalid" for a value outside the list' do
        expect(klass.new(page_size: 25).errors[:page_size]).to include('is invalid')
      end
    end

    context 'with a closed Range on a :float field' do
      let(:klass) do
        Class.new(described_class) do
          required :amount, :float, in: 1.0..10.0
        end
      end

      it 'accepts a value inside the range' do
        expect(klass.new(amount: 5.5)).to be_valid
      end

      it 'accepts the upper bound (inclusive Range)' do
        expect(klass.new(amount: 10.0)).to be_valid
      end

      it 'records "is invalid" for a value outside the range' do
        expect(klass.new(amount: 99.0).errors[:amount]).to include('is invalid')
      end
    end

    context 'with a half-open Range on an :integer field' do
      let(:klass) do
        Class.new(described_class) do
          required :height, :integer, in: 10..
        end
      end

      it 'accepts a value at or above the lower bound' do
        expect(klass.new(height: 10)).to be_valid
        expect(klass.new(height: 999_999)).to be_valid
      end

      it 'records "is invalid" below the lower bound' do
        expect(klass.new(height: 9).errors[:height]).to include('is invalid')
      end
    end

    context 'on a date field with a Range' do
      let(:klass) do
        Class.new(described_class) do
          required :on, :date, in: Date.new(2024, 1, 1)..Date.new(2024, 12, 31)
        end
      end

      it 'accepts dates inside the range' do
        expect(klass.new(on: '2024-06-15')).to be_valid
      end

      it 'rejects dates outside the range' do
        expect(klass.new(on: '2025-01-01').errors[:on]).to include('is invalid')
      end
    end

    context 'on a string-like type' do
      it 'raises ArgumentError at class load' do
        expect do
          Class.new(described_class) { required :s, :string, in: [1, 2, 3] }
        end.to raise_error(ArgumentError, /in: option does not apply to String/)
      end
    end

    context 'with neither Array nor Range' do
      it 'raises ArgumentError at class load' do
        expect do
          Class.new(described_class) { required :n, :integer, in: 'oops' }
        end.to raise_error(ArgumentError, /Array or Range/)
      end
    end
  end

  describe 'nil-exemption (consistent with format:)' do
    let(:klass) do
      Class.new(described_class) do
        optional :status, :string, enum: %w[on off]
        optional :page_size, :integer, in: [10, 20]
      end
    end

    it 'records no "is invalid" for a nil value on an optional enum field' do
      expect(klass.new(status: nil)).to be_valid
    end

    it 'records no "is invalid" for a nil value on an optional in field' do
      expect(klass.new(page_size: nil)).to be_valid
    end
  end

  describe 'interaction with required-presence' do
    let(:klass) do
      Class.new(described_class) do
        required :status, :string, enum: %w[on off]
      end
    end

    it 'records "is required" (not "is invalid") for nil on a required field' do
      expect(klass.new(status: nil).errors[:status]).to eq(['is required'])
    end
  end

  describe 'enum: combined with format:' do
    let(:klass) do
      Class.new(described_class) do
        required :code, :string, format: /\A[A-Z]+\z/, enum: %w[USD EUR JPY]
      end
    end

    it 'is valid only when both format and enum hold' do
      expect(klass.new(code: 'USD')).to be_valid
    end

    it 'records "is invalid" when only enum fails' do
      expect(klass.new(code: 'XYZ').errors[:code]).to include('is invalid')
    end

    it 'records "is invalid" when only format fails' do
      expect(klass.new(code: 'usd').errors[:code]).to include('is invalid')
    end

    it 'records a single "is invalid" no matter how many checks fail' do
      expect(klass.new(code: 'lowercase!').errors[:code]).to eq(['is invalid'])
    end
  end
end
