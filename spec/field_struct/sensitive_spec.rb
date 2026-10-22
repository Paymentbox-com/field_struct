# frozen_string_literal: true

require 'pp'

RSpec.describe 'the sensitive: field option' do
  def struct(const_name, &body)
    klass = Class.new(FieldStruct::Base)
    klass.class_eval(&body) if body
    stub_const(const_name, klass)
    klass
  end

  let(:payment) do
    struct('Payment') do
      required :card_number, :string, sensitive: true
      optional :cvv, :integer, sensitive: true
      optional :amount, :decimal
    end
  end

  describe 'inspect' do
    it 'shows [FILTERED] in place of a sensitive value' do
      record = payment.new(card_number: '4111111111111111', cvv: 123, amount: '9.99')
      expect(record.inspect).to eq('#<Payment card_number: [FILTERED], cvv: [FILTERED], amount: 0.999e1>')
    end

    it 'still shows nil, so a missing value stays visible' do
      expect(payment.new(card_number: 'x').inspect).to eq('#<Payment card_number: [FILTERED], cvv: nil, amount: nil>')
    end

    it 'masks a raw value kept by a coercion failure, and the error names only its class' do
      record = payment.new(card_number: 'x', cvv: '4111-not-a-number')
      expect(record.inspect).not_to include('4111')
      expect(record.inspect).to include('cvv: [FILTERED]')
      expect(record.errors[:cvv]).to eq(['could not be coerced: Integer fields expect a base-10 integer, got a String that is not one'])
    end

    it 'masks inside a nested struct and an array of them' do
      payment_class = payment
      order = struct('Order') do
        required :payment, payment_class
        optional :history, :array, of: payment_class
      end
      record = order.new(payment: {card_number: '4111111111111111'}, history: [{card_number: '4222222222222222'}])
      expect(record.inspect).not_to match(/4111|4222/)
      expect(record.inspect).to include('card_number: [FILTERED]')
    end

    it 'masks pp / pretty_inspect too' do
      expect(payment.new(card_number: '4111111111111111').pretty_inspect).not_to include('4111')
    end

    it 'exposes the placeholder as FieldStruct::FILTERED' do
      expect(FieldStruct::FILTERED).to eq('[FILTERED]')
    end
  end

  describe 'data paths are not masked' do
    let(:record) { payment.new(card_number: '4111111111111111', cvv: 123) }

    it 'returns the real value from the reader, attributes, to_h and pattern matching' do
      expect(record.card_number).to eq('4111111111111111')
      expect(record.attributes[:card_number]).to eq('4111111111111111')
      expect(record.to_h[:cvv]).to eq(123)
      expect(record.deconstruct_keys([:card_number])).to eq(card_number: '4111111111111111')
    end

    it 'round-trips through as_json / to_json / from_json' do
      expect(record.as_json[:card_number]).to eq('4111111111111111')
      expect(payment.from_json(record.to_json)).to eq(record)
    end
  end

  describe 'declaration' do
    it 'exposes Field#sensitive?, false by default' do
      expect(payment.metadata[:card_number].sensitive?).to be(true)
      expect(payment.metadata[:amount].sensitive?).to be(false)
    end

    it 'keeps sensitive out of Field#options' do
      expect(payment.metadata[:card_number].options).not_to have_key(:sensitive)
    end

    it 'shows sensitive in Field#inspect only when set' do
      expect(payment.metadata[:card_number].inspect).to eq('#<FieldStruct::Field :card_number String required sensitive>')
      expect(payment.metadata[:amount].inspect).to eq('#<FieldStruct::Field :amount BigDecimal>')
    end

    it 'adds sensitive: true to Metadata#to_h only when set' do
      schema = payment.metadata.to_h
      expect(schema[:card_number]).to include(sensitive: true)
      expect(schema[:amount]).not_to have_key(:sensitive)
    end

    it 'marks the field in describe' do
      expect(payment.describe).to include('card_number (String, required, sensitive)')
      expect(payment.describe).to include('amount (BigDecimal, optional)')
    end

    it 'applies to every type, including nested, array and union fields' do
      payment_class = payment
      klass = struct('Everything') do
        optional :a, :value, sensitive: true
        optional :b, payment_class, sensitive: true
        optional :c, :array, of: :string, sensitive: true
        optional :d, :union, of: %i[integer string], sensitive: true
        optional :e, :date, sensitive: true
      end
      expect(klass.metadata.map(&:sensitive?)).to all(be(true))
    end

    it 'accepts sensitive: false' do
      klass = struct('Plain') { optional :a, :string, sensitive: false }
      expect(klass.metadata[:a].sensitive?).to be(false)
      expect(klass.new(a: 'x').inspect).to eq('#<Plain a: "x">')
    end

    it 'refuses a non-Boolean at declaration, naming the class' do
      expect { struct('Bad') { optional :a, :string, sensitive: 'yes' } }
        .to raise_error(ArgumentError, 'sensitive: must be true or false, got String')
    end

    it 'is inherited with the field' do
      child = Class.new(payment)
      expect(child.metadata[:card_number].sensitive?).to be(true)
    end
  end
end
