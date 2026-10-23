# frozen_string_literal: true

# `new` gives every field its default before it assigns the input. A field
# whose default is nil and whose key the input carries has that default pass
# reduced to storing nil: the setter runs once, for the given value.
RSpec.describe FieldStruct::Base do
  describe 'the default pass in new' do
    let(:log) { [] }
    let(:klass) do
      calls = log
      parent = Class.new(described_class) do
        field :name, :string
        field :nick, :string, default: 'anon'
      end
      Class.new(parent) do
        define_method(:name=) do |value|
          calls << value
          super(value)
        end
      end
    end

    it 'runs an overridden setter once for a key the input gives' do
      klass.new(name: 'Al')
      klass.new('name' => 'Bo')
      expect(log).to eq(%w[Al Bo])
    end

    it 'still runs the setter with nil for a key the input leaves out' do
      klass.new(nick: 'x')
      expect(log).to eq([nil])
    end

    it 'keeps ivar order, values and errors' do
      record = klass.new(nick: 'x', name: 'Al')
      expect(record.instance_variables).to eq(%i[@errors @name @nick @_initialized])
      expect(record.attributes).to eq(name: 'Al', nick: 'x')
    end

    it 'keeps the order of errors' do
      strict = Class.new(described_class) do
        required :a, :string
        required :b, :string
        required :c, :string
      end
      expect(strict.new(c: nil, a: nil).errors.to_h.keys).to eq(%i[b c a])
    end

    context 'with coercion_policy :raise and a type that refuses nil' do
      let(:refuses_nil) do
        Class.new(FieldStruct::Types::Base) do
          def coerce(value, **)
            raise ArgumentError, 'nil is not accepted' if value.nil?

            value.to_s
          end
        end
      end
      let(:strict_klass) do
        type = refuses_nil
        Class.new(described_class) do
          coercion_policy :raise
          field :code, type
        end
      end

      it 'does not raise when the key is given' do
        expect(strict_klass.new(code: 'A1').code).to eq('A1')
      end

      it 'raises as before when the key is left out' do
        expect { strict_klass.new }.to raise_error(FieldStruct::CoercionError, /nil is not accepted/)
      end
    end
  end
end
