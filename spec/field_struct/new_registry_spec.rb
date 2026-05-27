# frozen_string_literal: true

RSpec.describe 'FieldStruct.new_registry' do
  describe 'building a new registry' do
    it 'returns a fresh Registry instance' do
      registry = FieldStruct.new_registry
      expect(registry).to be_a(FieldStruct::Registry)
    end

    it 'defaults the parent to FieldStruct.types' do
      registry = FieldStruct.new_registry
      expect(registry.parent).to equal(FieldStruct.types)
    end

    it 'can be passed an explicit parent' do
      parent = FieldStruct.new_registry
      child = FieldStruct.new_registry(parent)
      expect(child.parent).to equal(parent)
    end

    it 'supports an unparented registry via parent: nil' do
      registry = FieldStruct.new_registry(nil)
      expect(registry.parent).to be_nil
    end
  end

  describe 'configuration block' do
    let(:money_type) { Class.new(FieldStruct::Types::Base) }

    it 'evaluates the block in the new registry instance scope' do
      money = money_type
      registry = FieldStruct.new_registry { register :money, money }
      expect(registry.lookup(:money)).to equal(money)
    end

    it 'is optional — no block is allowed' do
      expect { FieldStruct.new_registry }.not_to raise_error
    end

    it 'has access to all Registry instance methods inside the block' do
      money = money_type
      registry = FieldStruct.new_registry do
        register :money, money
        register :cash, :money # alias
      end
      expect(registry.lookup(:cash)).to equal(money)
    end

    it 'preserves the parent-chain semantics on inherited types' do
      registry = FieldStruct.new_registry { register :money, FieldStruct::Types::Base }
      # Inherited :string still resolves from FieldStruct.types
      expect(registry.lookup(:string)).to eq(FieldStruct::Types::String)
    end
  end

  describe 'use case — namespace registry pattern' do
    it 'matches the documented namespace pattern' do
      money_type = Class.new(FieldStruct::Types::Base)

      namespace = Module.new
      stub_const('NewRegistryDemo', namespace)
      namespace.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct.new_registry { register :money, money_type }
      end

      order_class = Class.new(FieldStruct::Base)
      stub_const('NewRegistryDemo::Order', order_class)
      order_class.class_eval do
        # Define a minimal coerce so the field can construct without raising
        # — we only care that the registry-chain resolution finds the type.
        money_type.define_method(:coerce) { |value, _options = {}| value }
        money_type.define_method(:ruby_type) { Numeric }

        field :amount, :money
      end

      expect(order_class.metadata[:amount].type).to equal(money_type)
    end
  end
end
