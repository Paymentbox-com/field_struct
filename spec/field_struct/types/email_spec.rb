# frozen_string_literal: true

RSpec.describe FieldStruct::Types::Email do
  describe 'default_format' do
    it 'matches common email shapes' do
      %w[
        alice@example.com
        a.b+c@sub.example.co.uk
        x@y.z
      ].each { |email| expect(described_class.default_format).to match(email) }
    end

    it 'rejects malformed addresses' do
      [
        'no-at-sign',
        '@no-local.com',
        'no-domain@',
        'no-tld@example',
        'two@@signs.com',
        'has space@example.com',
        ''
      ].each { |bad| expect(described_class.default_format).not_to match(bad) }
    end
  end

  describe 'integration via the DSL' do
    let(:klass) do
      Class.new(FieldStruct::Base) { required :contact, :email }
    end

    it 'auto-populates the field options with default_format' do
      expect(klass.metadata[:contact].options[:format]).to eq(described_class::DEFAULT_FORMAT)
    end

    it 'accepts a valid email' do
      expect(klass.new(contact: 'alice@example.com')).to be_valid
    end

    it 'records "is invalid" for a malformed email' do
      expect(klass.new(contact: 'not-an-email').errors[:contact]).to include('is invalid')
    end
  end
end
