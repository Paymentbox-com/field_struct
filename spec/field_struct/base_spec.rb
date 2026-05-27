# frozen_string_literal: true

RSpec.describe FieldStruct::Base do
  describe 'declaring a field' do
    let(:klass) do
      Class.new(described_class) do
        field :name, :string
      end
    end

    it 'adds the field to the class metadata' do
      expect(klass.attribute_names).to eq([:name])
    end

    it 'defines a getter method' do
      expect(klass.new.respond_to?(:name)).to be true
    end

    it 'defines a setter method' do
      expect(klass.new.respond_to?(:name=)).to be true
    end

    it 'stores the resolved type class on the field' do
      expect(klass.metadata[:name].type).to eq(FieldStruct::Types::String)
    end

    context 'with an unknown type name' do
      it 'raises KeyError at declaration time' do
        expect do
          Class.new(described_class) { field :foo, :nope_not_a_type }
        end.to raise_error(KeyError)
      end
    end
  end

  describe 'constructing an instance' do
    let(:klass) do
      Class.new(described_class) do
        field :name, :string
        field :age, :integer
      end
    end

    it 'assigns values from a symbol-keyed hash' do
      instance = klass.new(name: 'Alice', age: 30)
      expect(instance.name).to eq('Alice')
      expect(instance.age).to eq(30)
    end

    it 'assigns values from a string-keyed hash' do
      instance = klass.new('name' => 'Alice', 'age' => 30)
      expect(instance.name).to eq('Alice')
      expect(instance.age).to eq(30)
    end

    it 'leaves omitted attributes nil by default' do
      instance = klass.new
      expect(instance.name).to be_nil
      expect(instance.age).to be_nil
    end

    it 'uses field defaults for omitted attributes' do
      defaulted = Class.new(described_class) do
        field :name, :string, default: 'Anon'
      end
      expect(defaulted.new.name).to eq('Anon')
    end

    it 'still coerces a provided value when a default exists' do
      defaulted = Class.new(described_class) do
        field :age, :integer, default: 0
      end
      expect(defaulted.new(age: '42').age).to eq(42)
    end

    it 'ignores unknown attributes in the input hash' do
      expect { klass.new(name: 'Alice', age: 30, extra: 'ignored') }.not_to raise_error
    end
  end

  describe 'the setter pipeline' do
    let(:klass) do
      Class.new(described_class) do
        field :age, :integer
      end
    end

    it 'coerces values via the resolved type' do
      instance = klass.new(age: '42')
      expect(instance.age).to eq(42)
    end

    it 'coerces later assignments through the same pipeline' do
      instance = klass.new(age: 30)
      instance.age = '99'
      expect(instance.age).to eq(99)
    end
  end

  describe 'instance-level attributes / attribute_names' do
    let(:klass) do
      Class.new(described_class) do
        field :name, :string
        field :age, :integer
      end
    end

    it 'returns the current attribute values as a hash' do
      instance = klass.new(name: 'Alice', age: '30')
      expect(instance.attributes).to eq(name: 'Alice', age: 30)
    end

    it 'returns a fresh hash each call' do
      instance = klass.new(name: 'Alice', age: 30)
      expect(instance.attributes).not_to equal(instance.attributes)
    end

    it 'delegates attribute_names to the class' do
      expect(klass.new.attribute_names).to eq(%i[name age])
    end
  end

  describe 'subclass inheritance' do
    let(:parent) do
      Class.new(described_class) do
        field :id, :integer
        field :name, :string
      end
    end

    it 'inherits parent fields' do
      child = Class.new(parent) do
        field :age, :integer
      end
      expect(child.attribute_names).to eq(%i[id name age])
    end

    it 'does not mutate the parent metadata when the child adds a field' do
      Class.new(parent) { field :age, :integer }
      expect(parent.attribute_names).to eq(%i[id name])
    end

    it 'lets the child shadow a parent field with a different type' do
      child = Class.new(parent) do
        field :id, :string
      end
      expect(child.metadata[:id].type).to eq(FieldStruct::Types::String)
      expect(parent.metadata[:id].type).to eq(FieldStruct::Types::Integer)
    end

    it 'gives the child its own working setter for the inherited field' do
      child = Class.new(parent)
      instance = child.new(name: 'Alice')
      expect(instance.name).to eq('Alice')
    end
  end

  describe 'namespace registry resolution' do
    let(:money_type) do
      Class.new(FieldStruct::Types::Base) do
        define_method(:coerce) { |value, _options = {}| "$#{value}" }
        define_method(:ruby_type) { String }
      end
    end

    it 'resolves the type via the containing module that responds to field_types' do
      namespace = Module.new
      stub_const('SliceFiveAcme', namespace)
      namespace.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct::Registry.new(FieldStruct.types)
      end
      namespace.field_types.register(:money, money_type)

      order_class = Class.new(described_class)
      stub_const('SliceFiveAcme::Order', order_class)
      order_class.class_eval { field :price, :money }

      expect(order_class.new(price: 42).price).to eq('$42')
    end

    it 'walks outward through multiple containing modules' do
      outer = Module.new
      inner = Module.new
      stub_const('SliceFiveOuter', outer)
      stub_const('SliceFiveOuter::Inner', inner)
      outer.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct::Registry.new(FieldStruct.types)
      end
      outer.field_types.register(:money, money_type)

      order_class = Class.new(described_class)
      stub_const('SliceFiveOuter::Inner::Order', order_class)
      order_class.class_eval { field :price, :money }

      expect(order_class.new(price: 7).price).to eq('$7')
    end

    it 'falls back to FieldStruct.types when no containing module responds to field_types' do
      klass = Class.new(described_class) { field :name, :string }
      expect(klass.new(name: 'Alice').name).to eq('Alice')
    end
  end
end
