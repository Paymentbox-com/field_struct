# frozen_string_literal: true

require 'bigdecimal'

# NaN and ±Infinity are not numbers a numeric field can hold. They must come
# back as an ordinary coercion failure — recorded under the field's
# coercion_policy — never escape as a FloatDomainError and never be stored as
# a valid value.
RSpec.describe FieldStruct::Base, 'non-finite numeric input' do
  let(:klass) do
    Class.new(described_class) do
      optional :n, :integer
      optional :f, :float
      optional :d, :decimal
    end
  end

  describe 'an :integer field' do
    it 'records a coercion error for Float::INFINITY instead of raising' do
      instance = klass.new(n: Float::INFINITY)
      expect(instance).not_to be_valid
      expect(instance.errors[:n]).to include(/could not be coerced/)
    end

    it 'records a coercion error for Float::NAN' do
      expect(klass.new(n: Float::NAN).errors[:n]).to include(/could not be coerced/)
    end

    it 'records a coercion error for a non-finite BigDecimal' do
      expect(klass.new(n: BigDecimal('-Infinity')).errors[:n]).to include(/could not be coerced/)
    end

    it 'records a coercion error for JSON 1e400 instead of raising' do
      instance = klass.from_json('{"n": 1e400}')
      expect(instance.errors[:n]).to include(/could not be coerced/)
    end

    it 'names the class in the message, never the value' do
      message = klass.new(n: Float::INFINITY).errors[:n].first
      expect(message).to include('Float')
      expect(message).not_to include('Infinity')
    end
  end

  describe 'a :float field' do
    [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |value|
      it "refuses the Float #{value}" do
        instance = klass.new(f: value)
        expect(instance).not_to be_valid
        expect(instance.errors[:f]).to include(/could not be coerced/)
      end
    end

    %w[NaN Infinity -Infinity 1e400].each do |value|
      it "refuses the String #{value.inspect}" do
        expect(klass.new(f: value).errors[:f]).to include(/could not be coerced/)
      end
    end

    it 'refuses JSON 1e400' do
      expect(klass.from_json('{"f": 1e400}').errors[:f]).to include(/could not be coerced/)
    end

    it 'names the class in the message, never the value' do
      message = klass.new(f: Float::INFINITY).errors[:f].first
      expect(message).to include('Float')
      expect(message).not_to include('Infinity')
    end
  end

  describe 'a :decimal field' do
    [Float::NAN, Float::INFINITY, -Float::INFINITY].each do |value|
      it "refuses the Float #{value}" do
        expect(klass.new(d: value).errors[:d]).to include(/could not be coerced/)
      end
    end

    %w[NaN Infinity -Infinity].each do |value|
      it "refuses the String #{value.inspect}" do
        instance = klass.new(d: value)
        expect(instance).not_to be_valid
        expect(instance.errors[:d]).to include(/could not be coerced/)
      end
    end

    it 'refuses a non-finite BigDecimal' do
      expect(klass.new(d: BigDecimal('NaN')).errors[:d]).to include(/could not be coerced/)
    end

    it 'refuses JSON 1e400' do
      expect(klass.from_json('{"d": 1e400}').errors[:d]).to include(/could not be coerced/)
    end

    it 'still accepts a large but finite decimal string' do
      instance = klass.new(d: '1e400')
      expect(instance).to be_valid
      expect(instance.d).to eq(BigDecimal('1e400'))
    end

    it 'names the class in the message, never the value' do
      message = klass.new(d: 'NaN').errors[:d].first
      expect(message).to include('String')
      expect(message).not_to include('NaN')
    end
  end

  describe 'a custom type that raises FloatDomainError' do
    it 'is handled by the coercion policy like any coercion failure' do
      domain_type = Class.new(FieldStruct::Types::Base) do
        def coerce(value, **)
          value.to_f.to_i # Float::INFINITY.to_i raises FloatDomainError
        end

        def ruby_type
          Integer
        end
      end
      registry = FieldStruct.new_registry { register :domainish, domain_type }
      ns = Module.new
      ns.define_singleton_method(:field_types) { registry }
      stub_const('NonFiniteNs', ns)
      record = Class.new(described_class)
      stub_const('NonFiniteNs::Record', record)
      record.class_eval { optional :v, :domainish }

      expect(record.new(v: Float::INFINITY).errors[:v]).to include(/could not be coerced/)
    end
  end
end
