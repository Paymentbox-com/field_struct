# frozen_string_literal: true

require 'pp'

# Payments data must never reach a log line. Every message FieldStruct builds
# about a value — an errors entry, a raised exception (and its cause chain),
# a sensitive field's inspect — names the value's class, never the value.
RSpec.describe 'Error messages never echo input values' do
  sentinel = 'SENTINEL-4111'

  # Bad input shaped to reach every refusal branch: strings that look like
  # numbers, dates, hex and exponents; containers; symbols; a Complex whose
  # inspect carries the digits.
  bad_inputs = [
    sentinel,
    "  #{sentinel}  ",
    "0x#{sentinel}",
    "1e#{sentinel}",
    "2026-01-01 #{sentinel}",
    "#{sentinel} 2026-01-01T10:00:00Z",
    "12:00:00 #{sentinel}",
    {card: sentinel},
    [sentinel],
    [{card: sentinel}],
    sentinel.to_sym,
    Complex(1, 4111)
  ].freeze

  # Options a type needs before it can be declared at all (its schema's
  # required options), plus option variants that take a different parse path.
  required_options = {
    FieldStruct::Types::Array => {of: :integer},
    FieldStruct::Types::Union => {of: %i[integer boolean]}
  }.freeze
  variants = {
    FieldStruct::Types::String => [{strict: true}],
    FieldStruct::Types::Integer => [{strict: true}, {base: 16}],
    FieldStruct::Types::Boolean => [{values: :english}],
    FieldStruct::Types::Date => [{format: :iso8601}, {format: :us}, {format: '%Y-%m-%d'}],
    FieldStruct::Types::Time => [{format: :iso8601}, {format: :rfc2822}, {format: :db}, {format: '%H:%M:%S'}],
    FieldStruct::Types::DateTime => [{format: :iso8601}, {format: :rfc2822}, {format: :db}]
  }.freeze

  nested = Class.new(FieldStruct::Base) do
    required :number, :integer
    required :expires, :date
  end

  # Every registered type — a type added to the base registry is covered
  # without touching this spec — and its variants, plus a nested struct.
  declarations = FieldStruct.types.type_classes.uniq.flat_map do |type_class|
    base = required_options.fetch(type_class, {})
    [base, *variants.fetch(type_class, []).map { |extra| base.merge(extra) }].map { |opts| [type_class, opts] }
  end
  declarations << [nested, {}]
  declarations << [FieldStruct::Types::Array, {of: nested}]

  def self.label(type_class, opts)
    "#{type_class.name || "nested struct"}#{" #{opts}" unless opts.empty?}"
  end

  # @return [Array<String>] the exception's message, its +original+'s and
  #   every message down its cause chain
  def messages_of(error)
    seen = []
    while error
      seen << "#{error.class}: #{error.message}"
      seen << "original #{error.original.class}: #{error.original.message}" if error.respond_to?(:original) && error.original
      error = error.cause
    end
    seen
  end

  declarations.each do |type_class, opts|
    context label(type_class, opts) do
      %i[keep_raw replace].each do |policy|
        it "keeps errors free of the value under :#{policy}" do
          klass = Class.new(FieldStruct::Base) { field :card, type_class, coercion_policy: policy, **opts }
          bad_inputs.each do |input|
            record = klass.new(card: input)
            rendered = [record.errors.full_messages, record.errors.to_h, record.errors.inspect].inspect
            expect(rendered).not_to include('4111'), "input #{input.inspect} leaked: #{rendered}"
          end
        end
      end

      it 'keeps the raised error and its cause chain free of the value under :raise' do
        klass = Class.new(FieldStruct::Base) { field :card, type_class, coercion_policy: :raise, **opts }
        bad_inputs.each do |input|
          klass.new(card: input)
        rescue StandardError => e
          rendered = messages_of(e).join(' / ')
          expect(rendered).not_to include('4111'), "input #{input.inspect} leaked: #{rendered}"
        end
      end

      it 'keeps inspect and pp free of a sensitive value, whatever was stored' do
        klass = Class.new(FieldStruct::Base) { field :card, type_class, sensitive: true, **opts }
        bad_inputs.each do |input|
          record = klass.new(card: input)
          rendered = [record.inspect, record.pretty_inspect].join
          expect(rendered).not_to include('4111'), "input #{input.inspect} leaked: #{rendered}"
        end
      end
    end
  end

  describe 'from_json' do
    let(:klass) { Class.new(FieldStruct::Base) { field :card, :string } }

    ['{"card":"SENTINEL-4111"', 'SENTINEL-4111', '{"card": SENTINEL-4111}',
     '"SENTINEL-4111"', '["SENTINEL-4111"]', '4111', "{\"card\":\"SENTINEL-4111\"\u0000"].each do |json|
      it "keeps the error for #{json.inspect} free of the input" do
        expect { klass.from_json(json) }.to raise_error(StandardError) { |e|
          expect(messages_of(e).join(' / ')).not_to include('4111')
        }
      end
    end
  end
  describe 'message text (class-only, still naming the field and the expected type)' do
    it 'boolean lists the accepted strings and names a refused String by class' do
      klass = Class.new(FieldStruct::Base) { field :ok, :boolean }
      expect(klass.new(ok: 'maybe').errors[:ok]).to eq(
        ['could not be coerced: Boolean fields expect true, false, 1, 0 or one of the strings ' \
         '"true", "1", "false", "0", got a String that is not one']
      )
    end

    it 'boolean names a refused non-String by class' do
      expect { FieldStruct::Types::Boolean.new.coerce({a: 1}) }.to raise_error(
        ArgumentError, 'Boolean fields expect true, false, 1, 0 or one of the strings ' \
                       '"true", "1", "false", "0", got Hash'
      )
    end

    it 'boolean lists a values: preset' do
      expect { FieldStruct::Types::Boolean.new.coerce('maybe', values: {truthy: %w[si], falsy: %w[no]}) }
        .to raise_error(ArgumentError, /one of the strings "si", "no", got a String that is not one/)
    end

    it 'union names its members and the input class' do
      union = FieldStruct::Types::Union.new([FieldStruct::Types::Integer.new, FieldStruct::Types::Boolean.new])
      expect { union.coerce('abc') }.to raise_error(TypeError, 'no union member (Integer | Boolean) could coerce String input')
    end

    it 'CoercionError names the field and the input class' do
      klass = Class.new(FieldStruct::Base) { field :cents, :integer, coercion_policy: :raise }
      expect { klass.new(cents: 'abc') }.to raise_error(
        FieldStruct::CoercionError,
        'could not coerce String input for cents: Integer fields expect a base-10 integer, got a String that is not one'
      )
    end

    it 'drops the Kernel conversion error from the cause chain' do
      klass = Class.new(FieldStruct::Base) { field :cents, :integer, coercion_policy: :raise }
      expect { klass.new(cents: 'abc') }.to raise_error(FieldStruct::CoercionError) { |e|
        expect(e.cause).to be(e.original)
        expect(e.original.cause).to be_nil
      }
    end

    it 'from_json names a non-object root by class' do
      klass = Class.new(FieldStruct::Base) { field :a, :string }
      expect { klass.from_json('["x"]') }.to raise_error(ArgumentError, 'from_json expects a JSON object root, got Array')
    end

    it 'from_json keeps the parse error class and position, drops the input' do
      klass = Class.new(FieldStruct::Base) { field :a, :string }
      expect { klass.from_json('{"a": secret}') }.to raise_error(EncodingError) { |e|
        expect(e.message).to match(/\Afrom_json could not parse its input as JSON \(.+ at line 1, column \d+\)\z/)
        expect(e.cause).to be_nil
      }
    end
  end
end
