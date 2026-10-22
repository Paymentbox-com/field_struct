# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'reserved field names' do
  # Names Base calls on its own instances. Pinned here so dropping one from
  # the list is a visible change.
  expected = %i[
    errors attributes attribute_names assign_attributes as_json to_json to_h
    to_model model_name inspect hash class send public_send freeze
    instance_variable_set deconstruct deconstruct_keys initialize
  ]

  it 'includes every name Base relies on' do
    expect(described_class::RESERVED_FIELD_NAMES).to include(*expected)
  end

  described_class::RESERVED_FIELD_NAMES.each do |reserved|
    it "refuses field :#{reserved} at declaration, naming the field" do
      expect { Class.new(described_class) { optional reserved, :string } }
        .to raise_error(ArgumentError, /\Afield :#{reserved} is reserved/)
    end
  end

  it 'refuses a reserved name given as a String' do
    expect { Class.new(described_class) { optional 'errors', :string } }
      .to raise_error(ArgumentError, /field :errors is reserved/)
  end

  it 'refuses it through required as well' do
    expect { Class.new(described_class) { required :hash, :string } }
      .to raise_error(ArgumentError, /field :hash is reserved/)
  end

  it 'explains what to do instead' do
    expect { Class.new(described_class) { optional :errors, :string } }
      .to raise_error(ArgumentError, /FieldStruct::Base relies on #errors.*serialize :json/)
  end

  %i[method name type id].each do |allowed|
    it "still allows field :#{allowed}" do
      klass = Class.new(described_class) { optional allowed, :string }
      instance = klass.new(allowed => 'card')

      expect(instance.public_send(allowed)).to eq('card')
      expect(instance).to be_valid
    end
  end

  it 'is frozen' do
    expect(described_class::RESERVED_FIELD_NAMES).to be_frozen
  end
end
