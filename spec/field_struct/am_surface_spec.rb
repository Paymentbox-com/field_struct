# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'ActiveModel-shaped surface' do
  let(:klass) do
    Class.new(described_class) do
      optional :name, :string
      optional :age, :integer
    end
  end

  describe '#to_h' do
    it 'returns the same hash as #attributes' do
      instance = klass.new(name: 'Alice', age: 30)
      expect(instance.to_h).to eq(name: 'Alice', age: 30)
    end
  end

  describe '#as_json' do
    it 'returns a hash of attributes for scalar values' do
      instance = klass.new(name: 'Alice', age: 30)
      expect(instance.as_json).to eq(name: 'Alice', age: 30)
    end

    it 'converts BigDecimal to its plain-form string' do
      decimal_klass = Class.new(described_class) { optional :price, :decimal }
      instance = decimal_klass.new(price: '3.14')
      expect(instance.as_json[:price]).to eq('3.14')
    end

    it 'converts Date/Time/DateTime to ISO-8601' do
      time_klass = Class.new(described_class) do
        optional :on, :date
        optional :at, :datetime
      end
      instance = time_klass.new(on: '2024-01-15', at: '2024-01-15T12:30:00Z')
      expect(instance.as_json[:on]).to eq('2024-01-15')
      expect(instance.as_json[:at]).to match(/\A2024-01-15T12:30:00/)
    end

    it 'recurses into arrays' do
      arr_klass = Class.new(described_class) do
        optional :prices, :array, of: :decimal
      end
      instance = arr_klass.new(prices: ['1.5', '2.75'])
      expect(instance.as_json[:prices]).to eq(['1.5', '2.75'])
    end
  end

  describe '#to_json' do
    it 'produces a JSON string via Oj' do
      instance = klass.new(name: 'Alice', age: 30)
      parsed = Oj.load(instance.to_json, mode: :compat)
      expect(parsed).to eq('name' => 'Alice', 'age' => 30)
    end
  end

  describe '#inspect' do
    it 'formats as #<ClassName field: value, ...>' do
      stub_const('SomeUser', klass)
      instance = SomeUser.new(name: 'Alice', age: 30)
      expect(instance.inspect).to eq('#<SomeUser name: "Alice", age: 30>')
    end

    it 'works for anonymous classes' do
      instance = klass.new(name: 'Alice', age: 30)
      expect(instance.inspect).to include('AnonymousFieldStruct')
    end
  end

  describe '.model_name and #model_name' do
    it 'exposes the class name on .model_name.name' do
      stub_const('SomeUserStruct', klass)
      expect(SomeUserStruct.model_name.name).to eq('SomeUserStruct')
    end

    it 'computes a snake_case singular and naive plural' do
      stub_const('UserAccount', klass)
      expect(UserAccount.model_name.singular).to eq('user_account')
      expect(UserAccount.model_name.plural).to eq('user_accounts')
    end

    it 'uses the last namespace segment for element' do
      stub_const('Acme::Order', klass)
      expect(Acme::Order.model_name.element).to eq('order')
    end

    it 'is callable on instances too' do
      stub_const('Person', klass)
      expect(Person.new.model_name.name).to eq('Person')
    end

    it 'returns a string-coercible value' do
      stub_const('SomeUser2', klass)
      expect("class: #{SomeUser2.model_name}").to eq('class: SomeUser2')
    end
  end

  describe '#to_model' do
    it 'returns self' do
      instance = klass.new(name: 'Alice')
      expect(instance.to_model).to equal(instance)
    end
  end
end
