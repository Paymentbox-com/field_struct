# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'frozen! macro' do
  describe 'default mutability' do
    let(:klass) { Class.new(described_class) { optional :name, :string } }

    it 'reports frozen_on_construct? false' do
      expect(klass.frozen_on_construct?).to be false
    end

    it 'does not freeze fresh instances' do
      expect(klass.new(name: 'A').frozen?).to be false
    end
  end

  describe 'a frozen! class' do
    let(:klass) do
      Class.new(described_class) do
        frozen!
        optional :name, :string
      end
    end

    it 'reports frozen_on_construct? true' do
      expect(klass.frozen_on_construct?).to be true
    end

    it 'returns frozen instances from .new' do
      expect(klass.new(name: 'A').frozen?).to be true
    end

    it 'raises FrozenError on any subsequent setter call' do
      instance = klass.new(name: 'A')
      expect { instance.name = 'B' }.to raise_error(FrozenError)
    end

    it 'still allows attribute reads' do
      instance = klass.new(name: 'A')
      expect(instance.name).to eq('A')
      expect(instance.attributes).to eq(name: 'A')
    end

    it 'still allows as_json / to_json' do
      instance = klass.new(name: 'A')
      expect(instance.as_json).to eq(name: 'A')
      expect(Oj.load(instance.to_json, mode: :compat)).to eq('name' => 'A')
    end

    it 'still allows valid? to run cross-field validators' do
      strict = Class.new(described_class) do
        frozen!
        optional :n, :integer

        validate do |record|
          record.errors.add(:base, 'n must be 1') unless record.n == 1
        end
      end

      bad = strict.new(n: 2)
      expect(bad.frozen?).to be true
      expect(bad).to be_invalid
      expect(bad.errors[:base]).to include('n must be 1')

      good = strict.new(n: 1)
      expect(good).to be_valid
    end
  end

  describe 'inheritance' do
    it 'inherits frozen_on_construct from the parent' do
      parent = Class.new(described_class) { frozen! }
      child = Class.new(parent)
      expect(child.frozen_on_construct?).to be true
    end

    it 'lets a child of a non-frozen parent opt in' do
      parent = Class.new(described_class) { optional :name, :string }
      child = Class.new(parent) { frozen! }
      expect(child.frozen_on_construct?).to be true
      expect(parent.frozen_on_construct?).to be false
    end
  end

  describe 'interaction with immutable!' do
    it 'frozen! is independent of immutable!' do
      klass = Class.new(described_class) do
        frozen!
        optional :name, :string
      end
      expect(klass.immutable?).to be false # frozen! alone does not flip immutable
    end

    it 'frozen! raises FrozenError, immutable! raises ImmutableError — distinguishable' do
      frozen_klass = Class.new(described_class) do
        frozen!
        optional :name, :string
      end
      immutable_klass = Class.new(described_class) do
        immutable!
        optional :name, :string
      end

      expect { frozen_klass.new(name: 'A').name = 'B' }
        .to raise_error(FrozenError)
      expect { immutable_klass.new(name: 'A').name = 'B' }
        .to raise_error(FieldStruct::ImmutableError)
    end

    it 'classes can stack both — frozen wins because Ruby checks frozen before our guard' do
      stacked = Class.new(described_class) do
        immutable!
        frozen!
        optional :name, :string
      end
      # @_initialized + immutable check happens first in the setter; this
      # triggers ImmutableError before the FrozenError would.
      expect { stacked.new(name: 'A').name = 'B' }
        .to raise_error(FieldStruct::ImmutableError)
    end
  end
end
