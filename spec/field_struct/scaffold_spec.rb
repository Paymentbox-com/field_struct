# frozen_string_literal: true

RSpec.describe FieldStruct::Scaffold do
  # Evaluate generated source in a throwaway *named* module and return it, so
  # the top-level `class X < FieldStruct::Base` definitions don't leak globally.
  # The module needs a real name because FieldStruct resolves types by walking
  # `self.name`'s namespace (an anonymous module has none).
  def build(source)
    mod = Module.new
    const = "ScaffoldEval#{object_id}_#{source.hash.abs}"
    Object.const_set(const, mod)
    mod.module_eval(source)
    mod
  ensure
    Object.send(:remove_const, const) if const && Object.const_defined?(const)
  end

  describe 'scalar typing' do
    it 'types real JSON scalars conservatively' do
      src = described_class.from_json({'name' => 'Al', 'age' => 30, 'rate' => 1.5, 'active' => true}, class_name: 'User')

      expect(src).to include('class User < FieldStruct::Base')
      expect(src).to match(/required :name, :string/)
      expect(src).to match(/required :age, :integer/)
      expect(src).to match(/required :rate, :float/)
      expect(src).to match(/required :active, :boolean/)
    end

    it 'keeps numeric-looking strings as :string, with a hint' do
      src = described_class.from_json({'amount' => '54.04', 'code' => '100'})

      expect(src).to match(/:amount, :string.*big_decimal/)
      expect(src).to match(/:code, :string.*integer/)
      expect(src).not_to match(/:amount, :big_decimal/)
    end

    it 'flags an always-empty field as optional with unknown type' do
      src = described_class.from_json({'surcharge' => ''})

      expect(src).to match(/optional :surcharge, :string.*unknown/)
    end
  end

  describe 'structure' do
    it 'emits a nested class before the parent and references it' do
      src = described_class.from_json({'merchant' => {'id' => '1', 'name' => 'X'}}, class_name: 'Payload')

      expect(src).to include('class Merchant < FieldStruct::Base')
      expect(src).to match(/required :merchant, Merchant/)
      expect(src.index('class Merchant')).to be < src.index('class Payload')
    end

    it 'types an array of scalars with of:' do
      src = described_class.from_json({'tags' => %w[a b]})
      expect(src).to match(/:tags, :array, of: :string/)
    end

    it 'generates an element class for an array of objects' do
      src = described_class.from_json({'items' => [{'sku' => 'A'}]}, class_name: 'Order')

      expect(src).to include('class Item < FieldStruct::Base')
      expect(src).to match(/:items, :array, of: Item/)
    end
  end

  describe 'multiple samples' do
    it 'resolves an empty field from another sample and marks it optional' do
      src = described_class.from_json([{'fee' => ''}, {'fee' => '2.50'}])

      expect(src).to match(/optional :fee, :string/)
      expect(src).to match(/:fee, :string.*big_decimal/)
    end

    it 'suggests an enum for a small repeated vocabulary' do
      src = described_class.from_json([{'kind' => 'cc'}, {'kind' => 'ach'}, {'kind' => 'cc'}])

      expect(src).to match(/:kind, :string.*enum/)
      expect(src).to include('"cc"')
    end

    it 'marks a key absent from some samples as optional with a presence ratio' do
      src = described_class.from_json([{'a' => 'x', 'b' => 'y'}, {'a' => 'z'}])

      expect(src).to match(%r{optional :b, :string.*present 1/2})
      expect(src).to match(/required :a, :string/)
    end
  end

  describe 'key sanitization' do
    it 'snake-cases non-identifier keys and emits a serialize mapping' do
      src = described_class.from_json({'firstName' => 'Al'}, class_name: 'P')

      expect(src).to match(/serialize :json, first_name: "firstName"/)
      expect(src).to match(/:first_name, :string/)
    end
  end

  describe 'input handling' do
    it 'accepts a JSON object string' do
      expect(described_class.from_json('{"a":"x"}')).to include('class Generated < FieldStruct::Base')
    end

    it 'accepts a JSON array string as a sample set' do
      expect(described_class.from_json('[{"a":"x"},{"a":"y"}]')).to match(/required :a, :string/)
    end

    it 'rejects an empty sample set' do
      expect { described_class.from_json('[]') }.to raise_error(ArgumentError, /no samples/)
    end

    it 'rejects non-object samples' do
      expect { described_class.from_json('[1, 2]') }.to raise_error(ArgumentError, /object/)
      expect { described_class.from_json('42') }.to raise_error(ArgumentError)
    end
  end

  describe 'end to end with a real webhook payload' do
    let(:json) { File.read(File.expand_path('../fixtures/json/nmi_card_sale.json', __dir__)) }

    it 'scaffolds into a usable, self-validating class' do
      src = described_class.from_json(json, class_name: 'NmiCardSale')

      expect(src).to include('class BillingAddress < FieldStruct::Base')
      expect(src).to include('class NmiCardSale < FieldStruct::Base')

      mod = build(src)
      klass = mod.const_get('NmiCardSale')
      instance = klass.from_json(json)

      expect(instance).to be_a(klass)
      expect(instance.valid?).to be(true)
      expect(instance.merchant).to be_a(mod.const_get('Merchant'))
      expect(instance.billing_address.city).to eq('New York City')
      expect(instance.features.is_test_mode).to be(true)
    end
  end
end
