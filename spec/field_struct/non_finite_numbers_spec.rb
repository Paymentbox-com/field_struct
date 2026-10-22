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

  describe 'a union with a :string member' do
    let(:union_klass) do
      Class.new(described_class) do
        optional :i, :union, of: %i[integer string]
        optional :d, :union, of: %i[decimal string]
        optional :s, :union, of: %i[string integer]
      end
    end

    it 'refuses Float::NAN rather than falling through to "NaN"' do
      instance = union_klass.new(i: Float::NAN)
      expect(instance).not_to be_valid
      expect(instance.errors[:i]).to include(/could not be coerced/)
    end

    it 'refuses Float::INFINITY rather than falling through to "Infinity"' do
      expect(union_klass.new(d: Float::INFINITY).errors[:d]).to include(/could not be coerced/)
    end

    it 'refuses a non-finite BigDecimal' do
      expect(union_klass.new(i: BigDecimal('NaN')).errors[:i]).to include(/could not be coerced/)
    end

    it 'refuses JSON 1e400' do
      instance = union_klass.from_json('{"i": 1e400}')
      expect(instance).not_to be_valid
      expect(instance.errors[:i]).to include(/could not be coerced/)
    end

    it 'refuses a non-finite number even when :string is the first member' do
      expect(union_klass.new(s: -Float::INFINITY).errors[:s]).to include(/could not be coerced/)
    end

    it 'names the class in the message, never the value' do
      message = union_klass.new(i: Float::NAN).errors[:i].first
      expect(message).to include('Float')
      expect(message).not_to include('NaN')
    end

    it 'still lets a finite Float through to its members' do
      expect(union_klass.new(i: 3.9).i).to eq(3)
    end
  end

  describe 'a Complex value' do
    it 'records a coercion error on an :integer field instead of raising' do
      expect(klass.new(n: Complex(1, 2)).errors[:n]).to include(/could not be coerced/)
    end

    it 'records a coercion error on a :float field instead of raising' do
      expect(klass.new(f: Complex(1, 2)).errors[:f]).to include(/could not be coerced/)
    end

    it 'names the class in the message, never the value' do
      [klass.new(n: Complex(1, 2)).errors[:n].first, klass.new(f: Complex(1, 2)).errors[:f].first].each do |message|
        expect(message).to include('Complex')
        expect(message).not_to include('1+2i')
      end
    end
  end

  describe 'messages from failed numeric parsing' do
    it ':float names the class, never the value, for an unparseable String' do
      %w[NaN Infinity abc].each do |raw|
        message = klass.new(f: raw).errors[:f].first
        expect(message).to include('String')
        expect(message).not_to include(raw)
      end
    end

    it ':decimal names the class, never the value, for an unparseable String' do
      message = klass.new(d: 'abc').errors[:d].first
      expect(message).to include('String')
      expect(message).not_to include('abc')
    end

    it ':decimal names the class, never the value, for a Rational' do
      instance = klass.new(d: Rational(1, 3))
      expect(instance.errors[:d]).to include(/could not be coerced/)
      expect(instance.errors[:d].first).to include('Rational')
      expect(instance.errors[:d].first).not_to include('1/3')
    end
  end

  describe 'a custom type that raises a RangeError' do
    [
      ['FloatDomainError', ->(value) { value.to_f.to_i }],
      ['plain RangeError', ->(_value) { raise RangeError, 'out of range' }]
    ].each do |label, body|
      it "handles a #{label} through the coercion policy" do
        range_type = Class.new(FieldStruct::Types::Base) do
          define_method(:coerce) { |value, **| body.call(value) }
          define_method(:ruby_type) { Integer }
        end
        registry = FieldStruct.new_registry { register :rangeish, range_type }
        ns = Module.new
        ns.define_singleton_method(:field_types) { registry }
        stub_const('NonFiniteNs', ns)
        record = Class.new(described_class)
        stub_const('NonFiniteNs::Record', record)
        record.class_eval { optional :v, :rangeish }

        expect(record.new(v: Float::INFINITY).errors[:v]).to include(/could not be coerced/)
      end
    end
  end
end
