# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'values: option on :boolean' do
  describe 'explicit Hash form' do
    let(:klass) do
      Class.new(described_class) do
        required :active, :boolean,
          values: {truthy: %w[on yes y], falsy: %w[off no n]}
      end
    end

    it 'accepts strings from the configured truthy list' do
      expect(klass.new(active: 'on').active).to be true
      expect(klass.new(active: 'YES').active).to be true # case-insensitive
      expect(klass.new(active: 'y').active).to be true
    end

    it 'accepts strings from the configured falsy list' do
      expect(klass.new(active: 'off').active).to be false
      expect(klass.new(active: 'NO').active).to be false
    end

    it 'rejects strings outside the custom vocabulary (via the class coercion_policy)' do
      instance = klass.new(active: 'true')
      expect(instance.errors[:active]).to include(/coerce/)
    end

    it 'still accepts literal true/false / 0/1 (those are not vocabulary-gated)' do
      expect(klass.new(active: true).active).to be true
      expect(klass.new(active: false).active).to be false
      expect(klass.new(active: 1).active).to be true
      expect(klass.new(active: 0).active).to be false
    end
  end

  describe 'Symbol preset form' do
    let(:klass) do
      Class.new(described_class) do
        required :flag, :boolean, values: :english_yes_no
      end
    end

    it 'resolves to the named preset at declaration time' do
      expect(klass.metadata[:flag].options[:values]).to eq(
        truthy: %w[true yes y on 1],
        falsy: %w[false no n off 0]
      )
    end

    it 'accepts every string in the preset' do
      %w[true yes y on 1].each do |s|
        expect(klass.new(flag: s).flag).to be(true), "expected #{s.inspect} -> true"
      end
      %w[false no n off 0].each do |s|
        expect(klass.new(flag: s).flag).to be(false), "expected #{s.inspect} -> false"
      end
    end
  end

  describe 'unknown preset name' do
    it 'raises ArgumentError at class load' do
      expect do
        Class.new(described_class) do
          required :flag, :boolean, values: :no_such_preset
        end
      end.to raise_error(ArgumentError, /unknown :boolean values preset/)
    end
  end

  describe 'non-Hash, non-Symbol value' do
    it 'raises ArgumentError at class load' do
      expect do
        Class.new(described_class) do
          required :flag, :boolean, values: 'oops'
        end
      end.to raise_error(ArgumentError, /Hash.*Symbol/)
    end
  end

  describe 'no values: option (default vocabulary)' do
    let(:klass) do
      Class.new(described_class) { required :flag, :boolean }
    end

    it 'uses the default true/false/1/0 vocabulary' do
      expect(klass.new(flag: 'true').flag).to be true
      expect(klass.new(flag: 'false').flag).to be false
    end

    it 'rejects strings outside the default (via the class coercion_policy)' do
      instance = klass.new(flag: 'yes')
      expect(instance.errors[:flag]).to include(/coerce/)
    end
  end

  describe 'subclass-level default override' do
    it 'a Boolean subclass with a different default_truthy/default_falsy works without values:' do
      yes_no = Class.new(FieldStruct::Types::Boolean) do
        def self.default_truthy
          %w[yes y on]
        end

        def self.default_falsy
          %w[no n off]
        end
      end
      stub_const('YesNoBoolean', yes_no)

      acme = Module.new
      stub_const('AcmeYesNo', acme)
      acme.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct.new_registry { register :yes_no, YesNoBoolean }
      end

      klass = Class.new(described_class)
      stub_const('AcmeYesNo::Survey', klass)
      klass.class_eval { required :consent, :yes_no }

      expect(klass.new(consent: 'yes').consent).to be true
      expect(klass.new(consent: 'no').consent).to be false
    end
  end
end
