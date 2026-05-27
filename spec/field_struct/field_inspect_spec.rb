# frozen_string_literal: true

require 'pp' # for #pretty_inspect

RSpec.describe FieldStruct::Field, '#inspect / #pretty_print' do
  let(:klass) do
    addr = Class.new(FieldStruct::Base) { required :street, :string }
    stub_const('InspectSpecAddress', addr)

    Class.new(FieldStruct::Base) do
      required :name, :string
      optional :level, :string, enum: %w[beginner pro]
      optional :age, :integer, default: 0, description: 'Age in years'
      required :score, :float, round: 2
      required :address, addr
      optional :tags, :array, of: :string
      optional :addresses, :array, of: addr
      optional :payload, :union, of: %i[string integer]
      optional :on, :date, coercion_policy: :raise
    end
  end

  describe '#inspect' do
    it 'shows :name with the type class basename' do
      expect(klass.metadata[:name].inspect).to eq('#<FieldStruct::Field :name String required>')
    end

    it 'omits "required" for optional fields' do
      expect(klass.metadata[:level].inspect).to include(':level String')
      expect(klass.metadata[:level].inspect).not_to include('required')
    end

    it 'surfaces the default when non-nil' do
      expect(klass.metadata[:age].inspect).to include('default=0')
    end

    it 'surfaces description when set' do
      expect(klass.metadata[:age].inspect).to include('description="Age in years"')
    end

    it 'surfaces coercion_policy when set' do
      expect(klass.metadata[:on].inspect).to include('coercion_policy=:raise')
    end

    it 'surfaces enum / round / format options inline' do
      expect(klass.metadata[:level].inspect).to include('enum=["beginner", "pro"]')
      expect(klass.metadata[:score].inspect).to include('round=2')
    end

    it 'shows Nested with the wrapped struct class name' do
      expect(klass.metadata[:address].inspect).to include('Nested(InspectSpecAddress)')
    end

    it 'shows Union with member type basenames joined by |' do
      expect(klass.metadata[:payload].inspect).to include('Union(String | Integer)')
    end

    it 'shows Array of stock symbol type with the basename' do
      expect(klass.metadata[:tags].inspect).to include('of_type=String')
    end

    it 'shows Array of nested with Nested(ClassName)' do
      expect(klass.metadata[:addresses].inspect).to include('of_type=Nested(InspectSpecAddress)')
    end

    it 'does not dump the @options Hash via reflection' do
      expect(klass.metadata[:name].inspect).not_to include('@options=')
      expect(klass.metadata[:name].inspect).not_to include('@type_instance=')
    end
  end

  describe '#pretty_print' do
    it 'produces the same output as #inspect via pp' do
      field = klass.metadata[:level]
      expect(field.pretty_inspect.strip).to eq(field.inspect)
    end
  end
end
