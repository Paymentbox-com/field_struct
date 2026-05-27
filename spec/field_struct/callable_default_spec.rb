# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'callable default' do
  describe 'a literal default' do
    let(:klass) do
      Class.new(described_class) { optional :name, :string, default: 'Anon' }
    end

    it 'is used as-is when no value is provided' do
      expect(klass.new.name).to eq('Anon')
    end
  end

  describe 'a Lambda default' do
    let(:klass) do
      Class.new(described_class) do
        optional :token, :string, default: -> { "tok-#{SecureRandom.hex(2)}" }
      end
    end

    before { require 'securerandom' }

    it 'invokes the lambda once per instance' do
      a = klass.new.token
      b = klass.new.token
      expect(a).to match(/\Atok-\h{4}\z/)
      expect(b).to match(/\Atok-\h{4}\z/)
      expect(a).not_to eq(b) # statistically — collisions are astronomically rare
    end
  end

  describe 'a Proc default' do
    let(:klass) do
      Class.new(described_class) do
        optional :n, :integer, default: proc { 42 }
      end
    end

    it 'invokes the proc and coerces the result through the setter pipeline' do
      expect(klass.new.n).to eq(42)
    end
  end

  describe 'a Method default' do
    let(:klass) do
      Class.new(described_class) do
        optional :now, :datetime, default: Time.method(:now)
      end
    end

    it 'invokes the method and coerces the result' do
      result = klass.new.now
      expect(result).to be_a(DateTime)
    end
  end

  describe 'a callable default + a user-provided value' do
    let(:klass) do
      Class.new(described_class) { optional :token, :string, default: -> { 'computed' } }
    end

    it 'the user value wins over the computed default' do
      expect(klass.new(token: 'explicit').token).to eq('explicit')
    end
  end

  describe 'a callable default + required + omitted' do
    let(:klass) do
      Class.new(described_class) { required :token, :string, default: -> { 'computed' } }
    end

    it 'the callable produces a value that satisfies required-presence' do
      expect(klass.new).to be_valid
      expect(klass.new.token).to eq('computed')
    end
  end

  describe 'a callable default that returns nil' do
    let(:klass) do
      callable = -> { nil } # rubocop:disable Style/NilLambda
      Class.new(described_class) { optional :x, :string, default: callable }
    end

    it 'stores nil — same as default: nil' do
      expect(klass.new.x).to be_nil
    end
  end

  describe 'a callable that raises' do
    let(:klass) do
      Class.new(described_class) do
        optional :x, :string, default: -> { raise 'boom' }
      end
    end

    it 'propagates the error from .new' do
      expect { klass.new }.to raise_error(/boom/)
    end
  end
end
