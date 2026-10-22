# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'round: option on numeric types' do
  describe ':float with round:' do
    let(:klass) do
      Class.new(described_class) do
        required :amount, :float, round: 2
      end
    end

    it 'rounds the coerced value to N decimal places' do
      expect(klass.new(amount: 3.14159).amount).to eq(3.14)
    end

    it 'accepts a string input and rounds after coercion' do
      expect(klass.new(amount: '2.718281828').amount).to eq(2.72)
    end

    it 'applies on reassignment' do
      instance = klass.new(amount: 1.0)
      instance.amount = 9.99999
      expect(instance.amount).to eq(10.0)
    end

    it 'does not round when round: is not set (default)' do
      plain = Class.new(described_class) { required :amount, :float }
      expect(plain.new(amount: 3.14159).amount).to eq(3.14159)
    end

    it 'round: 0 rounds to integer-valued float' do
      zero = Class.new(described_class) { required :n, :float, round: 0 }
      expect(zero.new(n: 3.7).n).to eq(4.0)
    end

    it 'round: 0 keeps the value a Float' do
      zero = Class.new(described_class) { required :n, :float, round: 0 }
      expect(zero.new(n: 3.7).n).to be_a(Float)
    end

    it 'rounds a half away from zero' do
      zero = Class.new(described_class) { required :n, :float, round: 0 }
      expect(zero.new(n: 2.5).n).to eq(3.0)
      expect(zero.new(n: -2.5).n).to eq(-3.0)
    end
  end

  describe ':big_decimal with round:' do
    let(:klass) do
      Class.new(described_class) do
        required :price, :decimal, round: 2
      end
    end

    it 'rounds the BigDecimal to N decimal places' do
      expect(klass.new(price: '3.14159')).to be_valid
      expect(klass.new(price: '3.14159').price).to eq(BigDecimal('3.14'))
    end

    it 'preserves nil' do
      opt = Class.new(described_class) { optional :price, :decimal, round: 2 }
      expect(opt.new(price: nil).price).to be_nil
    end

    it 'does not round when round: is not set' do
      plain = Class.new(described_class) { required :price, :decimal }
      expect(plain.new(price: '3.14159').price).to eq(BigDecimal('3.14159'))
    end

    it 'round: 0 keeps the value a BigDecimal' do
      zero = Class.new(described_class) { required :price, :decimal, round: 0 }
      price = zero.new(price: '3.7').price
      expect(price).to be_a(BigDecimal)
      expect(price).to eq(BigDecimal('4'))
    end

    it 'rounds a half up' do
      expect(klass.new(price: '12.345').price).to eq(BigDecimal('12.35'))
      expect(klass.new(price: '-12.345').price).to eq(BigDecimal('-12.35'))
    end

    context "when the host has set BigDecimal's global rounding mode to banker's" do
      around do |example|
        saved = BigDecimal.mode(BigDecimal::ROUND_MODE)
        begin
          BigDecimal.mode(BigDecimal::ROUND_MODE, :banker)
          example.run
        ensure
          BigDecimal.mode(BigDecimal::ROUND_MODE, saved)
        end
      end

      it 'still rounds half up' do
        expect(klass.new(price: '12.345').price).to eq(BigDecimal('12.35'))
      end

      it 'still rounds half up at round: 0' do
        zero = Class.new(described_class) { required :price, :decimal, round: 0 }
        expect(zero.new(price: '2.5').price).to eq(BigDecimal('3'))
      end
    end
  end

  describe 'subclass-level default_round override' do
    it 'subclassing the type and overriding default_round changes the per-field default' do
      money_type = Class.new(FieldStruct::Types::BigDecimal) do
        def self.default_round
          2
        end
      end
      stub_const('MoneyType', money_type)

      acme = Module.new
      stub_const('AcmeRounding', acme)
      acme.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct.new_registry { register :money, MoneyType }
      end

      order = Class.new(described_class)
      stub_const('AcmeRounding::Order', order)
      order.class_eval do
        required :price, :money # no explicit round:, uses MoneyType.default_round
      end

      expect(order.new(price: '3.14159').price).to eq(BigDecimal('3.14'))
    end
  end
end
