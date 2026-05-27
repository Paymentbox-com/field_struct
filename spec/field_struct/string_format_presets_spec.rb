# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'format: Symbol presets on Email/UUID/URL' do
  describe ':email format presets' do
    it 'resolves :strict to a tighter regex at declaration time' do
      klass = Class.new(described_class) do
        required :email, :email, format: :strict
      end
      regex = klass.metadata[:email].options[:format]
      expect(regex).to be_a(Regexp)
      expect(regex).to match('alice@example.com')
      expect(regex).not_to match('weird..dots@no_underscore.example')
    end

    it 'resolves :permissive to a looser regex' do
      klass = Class.new(described_class) do
        required :email, :email, format: :permissive
      end
      regex = klass.metadata[:email].options[:format]
      expect(regex).to match('x@y') # would fail default :email regex
    end

    it 'still accepts an explicit Regexp' do
      klass = Class.new(described_class) do
        required :email, :email, format: /\A.+@example\.com\z/
      end
      expect(klass.metadata[:email].options[:format]).to eq(/\A.+@example\.com\z/)
    end

    it 'raises ArgumentError for an unknown preset name' do
      expect do
        Class.new(described_class) do
          required :email, :email, format: :no_such_preset
        end
      end.to raise_error(ArgumentError, /unknown :email format preset/)
    end
  end

  describe ':uuid format presets' do
    it 'resolves :v4 to a version-4-specific regex' do
      klass = Class.new(described_class) do
        required :id, :uuid, format: :v4
      end
      regex = klass.metadata[:id].options[:format]
      v4 = '550e8400-e29b-41d4-a716-446655440000'
      v1 = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'
      expect(regex).to match(v4)
      expect(regex).not_to match(v1)
    end

    it 'resolves :any_version to the default regex' do
      klass = Class.new(described_class) do
        required :id, :uuid, format: :any_version
      end
      expect(klass.metadata[:id].options[:format]).to eq(FieldStruct::Types::UUID.default_format)
    end
  end

  describe ':url format presets' do
    it 'resolves :https_only to an https-only regex' do
      klass = Class.new(described_class) do
        required :site, :url, format: :https_only
      end
      regex = klass.metadata[:site].options[:format]
      expect(regex).to match('https://example.com')
      expect(regex).not_to match('http://example.com')
    end

    it 'resolves :any_scheme to a broader regex' do
      klass = Class.new(described_class) do
        required :endpoint, :url, format: :any_scheme
      end
      regex = klass.metadata[:endpoint].options[:format]
      expect(regex).to match('ftp://example.com')
      expect(regex).to match('https://example.com')
    end
  end

  describe 'subclass-level preset override' do
    it 'a subclass can override presets to add or replace entries' do
      strict_email = Class.new(FieldStruct::Types::Email) do
        def self.presets
          super.merge(corporate: /\A[\w.]+@acme\.com\z/)
        end
      end
      stub_const('CorporateEmail', strict_email)

      acme = Module.new
      stub_const('AcmePresets', acme)
      acme.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct.new_registry { register :corp_email, CorporateEmail }
      end

      klass = Class.new(described_class)
      stub_const('AcmePresets::Employee', klass)
      klass.class_eval do
        required :work_email, :corp_email, format: :corporate
      end

      expect(klass.metadata[:work_email].options[:format]).to match('alice@acme.com')
      expect(klass.metadata[:work_email].options[:format]).not_to match('alice@elsewhere.com')
    end
  end
end
