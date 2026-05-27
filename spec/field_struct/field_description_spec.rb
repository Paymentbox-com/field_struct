# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'description / desc field option' do
  describe 'declaration with description:' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string, description: 'Primary contact email for the user'
      end
    end

    it 'stores the description on the Field' do
      expect(klass.metadata[:email].description).to eq('Primary contact email for the user')
    end

    it 'exposes the same value via the desc alias reader' do
      expect(klass.metadata[:email].desc).to eq('Primary contact email for the user')
    end
  end

  describe 'declaration with desc: (the shorter alias)' do
    let(:klass) do
      Class.new(described_class) do
        required :age, :integer, desc: 'Age in years'
      end
    end

    it 'stores the value under #description' do
      expect(klass.metadata[:age].description).to eq('Age in years')
    end

    it 'also reads back via #desc' do
      expect(klass.metadata[:age].desc).to eq('Age in years')
    end
  end

  describe 'declaration with both raises' do
    it 'raises ArgumentError when both description: and desc: are passed' do
      expect do
        Class.new(described_class) do
          required :x, :string, description: 'long form', desc: 'short form'
        end
      end.to raise_error(ArgumentError, /either description: or desc:/)
    end
  end

  describe 'default when neither is provided' do
    let(:klass) do
      Class.new(described_class) { required :name, :string }
    end

    it 'description is nil' do
      expect(klass.metadata[:name].description).to be_nil
    end

    it 'desc is nil' do
      expect(klass.metadata[:name].desc).to be_nil
    end
  end

  describe 'description is documentation metadata, not data' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string, description: 'The user name'
      end
    end

    it 'does not appear in #attributes' do
      instance = klass.new(name: 'Alice')
      expect(instance.attributes).to eq(name: 'Alice')
    end

    it 'does not appear in #as_json' do
      instance = klass.new(name: 'Alice')
      expect(instance.as_json).to eq(name: 'Alice')
    end

    it 'does not appear in deconstruct_keys (pattern matching)' do
      instance = klass.new(name: 'Alice')
      expect(instance.deconstruct_keys(nil)).to eq(name: 'Alice')
    end

    it 'does not appear in #options either — it is its own attribute on Field' do
      expect(klass.metadata[:name].options).not_to have_key(:description)
      expect(klass.metadata[:name].options).not_to have_key(:desc)
    end
  end

  describe 'inheritance' do
    let(:parent) do
      Class.new(described_class) do
        required :name, :string, description: 'parent says'
      end
    end

    it 'a subclass inherits the parent field with its description' do
      child = Class.new(parent)
      expect(child.metadata[:name].description).to eq('parent says')
    end

    it 'a subclass can re-declare the field to replace the description' do
      child = Class.new(parent) do
        required :name, :string, description: 'child says'
      end
      expect(child.metadata[:name].description).to eq('child says')
      expect(parent.metadata[:name].description).to eq('parent says')
    end

    it 'a subclass that re-declares without description: drops the parent description' do
      child = Class.new(parent) do
        required :name, :string
      end
      expect(child.metadata[:name].description).to be_nil
    end
  end

  describe 'introspection across the declared fields' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string, description: 'Primary contact email'
        required :first_name, :string, desc: 'Given name'
        optional :age, :integer
      end
    end

    it 'walks fields collecting their descriptions' do
      doc = klass.metadata.map { |f| [f.name, f.description] }
      expect(doc).to eq([
        [:email, 'Primary contact email'],
        [:first_name, 'Given name'],
        [:age, nil]
      ])
    end
  end
end
