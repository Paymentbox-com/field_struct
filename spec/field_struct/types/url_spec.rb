# frozen_string_literal: true

RSpec.describe FieldStruct::Types::URL do
  describe 'default_format' do
    it 'matches common http(s) URLs' do
      [
        'http://example.com',
        'https://example.com',
        'https://example.com/path',
        'https://example.com/path?q=v',
        'https://example.com/path#anchor',
        'https://sub.example.co.uk',
        'HTTPS://EXAMPLE.COM'
      ].each { |url| expect(described_class.default_format).to match(url) }
    end

    it 'rejects malformed URLs' do
      [
        'example.com',
        'http://',
        'ftp://example.com',
        'not a url',
        'https:// has space',
        ''
      ].each { |bad| expect(described_class.default_format).not_to match(bad) }
    end
  end

  describe 'integration via the DSL' do
    let(:klass) do
      Class.new(FieldStruct::Base) { required :site, :url }
    end

    it 'auto-populates the field options with default_format' do
      expect(klass.metadata[:site].options[:format]).to eq(described_class::DEFAULT_FORMAT)
    end

    it 'accepts a valid URL' do
      expect(klass.new(site: 'https://example.com')).to be_valid
    end

    it 'records "is invalid" for a malformed URL' do
      expect(klass.new(site: 'not-a-url').errors[:site]).to include('is invalid')
    end
  end
end
