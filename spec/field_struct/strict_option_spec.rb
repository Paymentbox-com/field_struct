# frozen_string_literal: true

require 'bigdecimal'

# Opt-in strict: true on :string (and its subtypes) and :integer. Defaults stay
# ActiveModel-lenient; strict only narrows what is accepted and never changes
# what an accepted value becomes.
RSpec.describe 'strict: option' do
  describe FieldStruct::Types::String do
    let(:type) { described_class.new }

    def coerce(value) = type.coerce(value, strict: true)

    describe 'accepting scalars and string-likes' do
      it 'keeps a String' do
        expect(coerce('hello')).to eq('hello')
      end

      it 'reads a Symbol' do
        expect(coerce(:hello)).to eq('hello')
      end

      it 'reads a finite real Numeric exactly as the default does' do
        [42, -7, 3.14, Rational(1, 2), BigDecimal('12.5')].each do |number|
          expect(coerce(number)).to eq(type.coerce(number))
        end
      end

      it 'reads an object that responds to #to_str' do
        string_like = Class.new { def to_str = 'acct-1' }.new
        expect(coerce(string_like)).to eq(type.coerce(string_like))
      end

      it 'passes nil through as nil' do
        expect(coerce(nil)).to be_nil
      end
    end

    describe 'refusing everything else' do
      {
        'a Hash' => {a: 1},
        'an Array' => [1, 2],
        'true' => true,
        'false' => false,
        'a plain object' => Object.new,
        'a Time' => Time.at(0),
        'a Complex' => Complex(1, 2)
      }.each do |label, value|
        it "refuses #{label} with a TypeError" do
          expect { coerce(value) }.to raise_error(TypeError, /strict: true/)
        end
      end

      it 'refuses a non-finite Numeric' do
        [Float::NAN, Float::INFINITY, BigDecimal('Infinity')].each do |number|
          expect { coerce(number) }.to raise_error(TypeError, /non-finite/)
        end
      end

      it 'names the class in the message, never the value' do
        expect { coerce({card: '4111111111111111'}) }.to raise_error(TypeError) { |error|
          expect(error.message).to include('Hash')
          expect(error.message).not_to include('4111')
        }
      end
    end

    it 'leaves the default (strict: false / absent) lenient' do
      expect(type.coerce({a: 1})).to eq({a: 1}.to_s)
      expect(type.coerce([1], strict: false)).to eq('[1]')
      expect(type.coerce([1], strict: nil)).to eq('[1]')
    end

    it 'applies to subtypes, which keep their own post-processing' do
      expect(FieldStruct::Types::ImmutableString.new.coerce(:a, strict: true)).to be_frozen
      expect(FieldStruct::Types::Binary.new.coerce('a', strict: true).encoding).to eq(Encoding::ASCII_8BIT)
      [FieldStruct::Types::ImmutableString, FieldStruct::Types::Binary, FieldStruct::Types::UUID].each do |klass|
        expect { klass.new.coerce([1], strict: true) }.to raise_error(TypeError)
      end
    end
  end

  describe FieldStruct::Types::Integer do
    let(:type) { described_class.new }

    def coerce(value, **options) = type.coerce(value, strict: true, **options)

    describe 'accepting whole numbers' do
      it 'keeps an Integer' do
        expect(coerce(12)).to eq(12)
      end

      it 'reads an integral Float, BigDecimal, Rational or real Complex' do
        expect(coerce(12.0)).to eq(12)
        expect(coerce(-3.0)).to eq(-3)
        expect(coerce(BigDecimal('12.000'))).to eq(12)
        expect(coerce(Rational(24, 2))).to eq(12)
        expect(coerce(Complex(12, 0))).to eq(12)
      end

      it 'reads integer strings in base 10, or in the declared base:' do
        expect(coerce(' 1_000 ')).to eq(1000)
        expect(coerce('010')).to eq(10)
        expect(coerce('1A', base: 16)).to eq(26)
      end

      it 'passes nil through as nil' do
        expect(coerce(nil)).to be_nil
      end
    end

    describe 'refusing anything that is not a whole number' do
      it 'refuses a non-integral numeric instead of truncating' do
        [12.7, -2.5, 0.1, BigDecimal('12.5'), Rational(25, 2), Complex(12.5, 0)].each do |number|
          expect { coerce(number) }.to raise_error(ArgumentError, /whole number/)
        end
      end

      it 'refuses float-shaped and prefixed strings, as the default does' do
        %w[12.7 12.0 1e3 0x1A].each do |string|
          expect { coerce(string) }.to raise_error(ArgumentError)
        end
      end

      it 'refuses an object Kernel#Integer would read through #to_i' do
        expect { coerce(Time.at(1_700_000_000)) }.to raise_error(ArgumentError, /whole number/)
      end

      it 'still refuses non-finite numbers and non-numerics' do
        expect { coerce(Float::INFINITY) }.to raise_error(ArgumentError, /non-finite/)
        expect { coerce(:twelve) }.to raise_error(TypeError)
      end

      it 'names the class in the message, never the value' do
        expect { coerce(1234.56) }.to raise_error(ArgumentError) { |error|
          expect(error.message).to include('Float')
          expect(error.message).not_to include('1234')
        }
      end
    end

    it 'leaves the default (strict: false / absent) truncating' do
      expect(type.coerce(12.7)).to eq(12)
      expect(type.coerce(12.7, strict: false)).to eq(12)
      expect(type.coerce(12.7, strict: nil)).to eq(12)
    end
  end

  describe 'declaring strict: on a field' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        optional :name, :string, strict: true
        optional :code, :uuid, strict: true
        optional :cents, :integer, strict: true
        optional :loose, :string
        optional :count, :integer
      end
    end

    it 'records a strict refusal as an ordinary coercion error' do
      record = klass.new(name: {a: 1}, cents: 12.7)
      expect(record).not_to be_valid
      expect(record.errors[:name].join).to include('Hash')
      expect(record.errors[:cents].join).to include('whole number')
    end

    it 'accepts what strict allows' do
      record = klass.new(name: :acme, cents: 1250.0)
      expect(record).to be_valid
      expect([record.name, record.cents]).to eq(['acme', 1250])
    end

    it 'leaves undeclared fields lenient' do
      record = klass.new(loose: {a: 1}, count: 12.7)
      expect(record).to be_valid
      expect([record.loose, record.count]).to eq([{a: 1}.to_s, 12])
    end

    it 'raises at declaration when strict: is not a Boolean' do
      expect do
        Class.new(FieldStruct::Base) { optional :name, :string, strict: 'yes' }
      end.to raise_error(ArgumentError, /strict: on String expects TrueClass or FalseClass, got String/)
      expect do
        Class.new(FieldStruct::Base) { optional :n, :integer, strict: 1 }
      end.to raise_error(ArgumentError, /strict: on Integer expects TrueClass or FalseClass, got Integer/)
    end

    it 'raises at declaration on a type that does not declare it, naming where it applies' do
      %i[float decimal symbol boolean date].each do |type_name|
        expect do
          Class.new(FieldStruct::Base) { optional :x, type_name, strict: true }
        end.to raise_error(ArgumentError, /strict: option does not apply to .*applies to: .*String.*Integer/)
      end
    end

    it 'is advertised by both types at runtime' do
      [FieldStruct::Types::String, FieldStruct::Types::Integer].each do |type_class|
        expect(type_class.option_schema.fetch(:strict)[:type]).to contain_exactly(TrueClass, FalseClass)
      end
    end
  end
end
