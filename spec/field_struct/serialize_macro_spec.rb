# frozen_string_literal: true

RSpec.describe FieldStruct::Base, '.serialize macro' do
  describe 'declaration stores a mapping on Metadata' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string
        required :first_name, :string
        required :last_name, :string

        serialize :json,
          first_name: 'firstName',
          last_name: 'lastName'
      end
    end

    it 'returns the declared mapping via metadata.serialization' do
      expect(klass.metadata.serialization(:json)).to eq(
        first_name: 'firstName',
        last_name: 'lastName'
      )
    end

    it 'exposes the format name on metadata.serializations' do
      expect(klass.metadata.serializations.keys).to eq([:json])
    end

    it 'omits unmapped fields from the mapping (they use canonical names)' do
      expect(klass.metadata.serialization(:json)).not_to have_key(:email)
    end

    it 'freezes the stored mapping' do
      expect(klass.metadata.serialization(:json)).to be_frozen
    end
  end

  describe 'normalizing mapping values' do
    it 'converts Symbol external names to Strings' do
      klass = Class.new(described_class) do
        required :first_name, :string
        serialize :json, first_name: :firstName
      end
      expect(klass.metadata.serialization(:json)).to eq(first_name: 'firstName')
    end

    it 'leaves String external names unchanged' do
      klass = Class.new(described_class) do
        required :first_name, :string
        serialize :json, first_name: 'firstName'
      end
      expect(klass.metadata.serialization(:json)[:first_name]).to eq('firstName')
    end
  end

  describe 'undeclared field references raise at class load' do
    it 'raises ArgumentError when a mapping key is not a declared field' do
      expect do
        Class.new(described_class) do
          required :email, :string
          serialize :json, typo_field: 'something'
        end
      end.to raise_error(ArgumentError, /undeclared field/)
    end

    it 'identifies every offending key in the message' do
      Class.new(described_class) do
        required :email, :string
        serialize :json, a: 'A', b: 'B'
      end
    rescue ArgumentError => e
      expect(e.message).to include(':a')
      expect(e.message).to include(':b')
    end

    it 'raises when serialize is called before the field is declared' do
      # Documentation: declare fields first, then serializations.
      expect do
        Class.new(described_class) do
          serialize :json, first_name: 'firstName'
          required :first_name, :string
        end
      end.to raise_error(ArgumentError, /undeclared field/)
    end
  end

  describe 'multi-format coexistence' do
    let(:klass) do
      Class.new(described_class) do
        required :first_name, :string
        serialize :json, first_name: 'firstName'
        serialize :csv, first_name: 'FirstName'
        serialize :xml, first_name: 'first-name'
      end
    end

    it 'stores each format independently' do
      expect(klass.metadata.serialization(:json)).to eq(first_name: 'firstName')
      expect(klass.metadata.serialization(:csv)).to eq(first_name: 'FirstName')
      expect(klass.metadata.serialization(:xml)).to eq(first_name: 'first-name')
    end

    it 'reports all declared format names' do
      expect(klass.metadata.serializations.keys).to contain_exactly(:json, :csv, :xml)
    end
  end

  describe 'last-write-wins on the same format name' do
    let(:klass) do
      Class.new(described_class) do
        required :first_name, :string
        serialize :json, first_name: 'firstName'
        serialize :json, first_name: 'OVERRIDE'
      end
    end

    it 'replaces the prior mapping entirely' do
      expect(klass.metadata.serialization(:json)).to eq(first_name: 'OVERRIDE')
    end
  end

  describe 'classes with no serialize declaration' do
    let(:klass) do
      Class.new(described_class) { required :email, :string }
    end

    it 'returns an empty mapping for any format name (implicit identity)' do
      expect(klass.metadata.serialization(:json)).to eq({})
      expect(klass.metadata.serialization(:csv)).to eq({})
    end

    it 'has no entries in serializations' do
      expect(klass.metadata.serializations).to be_empty
    end
  end

  describe 'inheritance' do
    let(:parent) do
      Class.new(described_class) do
        required :first_name, :string
        serialize :json, first_name: 'firstName'
      end
    end

    it 'a subclass inherits the parent mapping' do
      child = Class.new(parent)
      expect(child.metadata.serialization(:json)).to eq(first_name: 'firstName')
    end

    it 'a subclass can override the inherited mapping' do
      child = Class.new(parent) do
        serialize :json, first_name: 'fName'
      end
      expect(child.metadata.serialization(:json)).to eq(first_name: 'fName')
      expect(parent.metadata.serialization(:json)).to eq(first_name: 'firstName')
    end

    it 'a subclass can add a new format alongside an inherited one' do
      child = Class.new(parent) do
        serialize :csv, first_name: 'FNAME'
      end
      expect(child.metadata.serialization(:json)).to eq(first_name: 'firstName')
      expect(child.metadata.serialization(:csv)).to eq(first_name: 'FNAME')
      expect(parent.metadata.serializations.keys).to eq([:json])
    end

    it 'a subclass can reference inherited fields in a new mapping' do
      child = Class.new(parent) do
        required :last_name, :string
        serialize :csv,
          first_name: 'FNAME',
          last_name: 'LNAME'
      end
      expect(child.metadata.serialization(:csv)).to eq(
        first_name: 'FNAME',
        last_name: 'LNAME'
      )
    end
  end

  describe 'declaration returns self for chaining' do
    it 'returns the class so subsequent calls can chain' do
      klass = Class.new(described_class) do
        required :first_name, :string
      end
      expect(klass.serialize(:json, first_name: 'firstName')).to equal(klass)
    end
  end

  describe 'no behavior change yet (Phase A only declares; Phase B wires JSON I/O)' do
    let(:klass) do
      Class.new(described_class) do
        required :first_name, :string
        serialize :json, first_name: 'firstName'
      end
    end

    it 'to_json still emits canonical names (until Phase B)' do
      instance = klass.new(first_name: 'Alice')
      expect(Oj.load(instance.to_json, mode: :compat).keys).to eq(['first_name'])
    end

    it 'attributes/to_h are unaffected' do
      instance = klass.new(first_name: 'Alice')
      expect(instance.attributes).to eq(first_name: 'Alice')
      expect(instance.to_h).to eq(first_name: 'Alice')
    end
  end
end
