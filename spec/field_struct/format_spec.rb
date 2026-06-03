# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'format: option' do
  describe 'on a string field' do
    let(:klass) do
      Class.new(described_class) do
        optional :email, :string, format: /\A[^@\s]+@[^@\s]+\z/
      end
    end

    context 'with a value matching the regex' do
      it 'is valid and records no error' do
        instance = klass.new(email: 'alice@example.com')
        expect(instance).to be_valid
        expect(instance.errors[:email]).to be_empty
      end
    end

    context 'with a value that does not match' do
      it 'records an "is invalid" error' do
        instance = klass.new(email: 'not-an-email')
        expect(instance.errors[:email]).to include('is invalid')
      end
    end

    context 'on a later assignment' do
      it 'clears a prior format error when the new value matches' do
        instance = klass.new(email: 'bad')
        expect(instance.errors[:email]).not_to be_empty
        instance.email = 'good@example.com'
        expect(instance.errors[:email]).to be_empty
      end

      it 'introduces an error when reassigned to something bad' do
        instance = klass.new(email: 'good@example.com')
        instance.email = 'bad'
        expect(instance.errors[:email]).to include('is invalid')
      end
    end
  end

  describe 'with optional + nil' do
    let(:klass) do
      Class.new(described_class) do
        optional :email, :string, format: /\A[^@\s]+@[^@\s]+\z/
      end
    end

    it 'records no format error — format only checks non-missing values' do
      instance = klass.new(email: nil)
      expect(instance.errors[:email]).to be_empty
      expect(instance).to be_valid
    end

    it 'records no format error for an empty string either (string missing? is empty)' do
      instance = klass.new(email: '')
      expect(instance.errors[:email]).to be_empty
    end
  end

  describe 'with required + missing' do
    let(:klass) do
      Class.new(described_class) do
        required :email, :string, format: /\A[^@\s]+@[^@\s]+\z/
      end
    end

    it 'records only the required-presence error, not the format error' do
      instance = klass.new(email: nil)
      expect(instance.errors[:email]).to eq(['is required'])
    end
  end

  describe 'on an immutable_string field' do
    let(:klass) do
      Class.new(described_class) do
        optional :code, :immutable_string, format: /\A[A-Z]{3}\z/
      end
    end

    it 'still applies the format check' do
      expect(klass.new(code: 'USD').errors[:code]).to be_empty
      expect(klass.new(code: 'usd').errors[:code]).to include('is invalid')
    end
  end

  describe 'on a non-string-shaped field' do
    it 'raises ArgumentError at class-declaration time' do
      expect do
        Class.new(described_class) { optional :n, :integer, format: /\d+/ }
      end.to raise_error(ArgumentError, /format: option does not apply to Integer/)
    end
  end
end
