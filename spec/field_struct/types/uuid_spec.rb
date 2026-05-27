# frozen_string_literal: true

RSpec.describe FieldStruct::Types::UUID do
  let(:type) { described_class.new }

  describe 'coercing input' do
    it 'inherits String coercion (returns the string form)' do
      uuid = '550e8400-e29b-41d4-a716-446655440000'
      expect(type.coerce(uuid)).to eq(uuid)
    end

    it 'returns nil for nil input' do
      expect(type.coerce(nil)).to be_nil
    end
  end

  describe 'default_format' do
    it 'matches canonical RFC-4122 UUIDs in any version' do
      [
        '550e8400-e29b-41d4-a716-446655440000', # v1
        '6ba7b810-9dad-11d1-80b4-00c04fd430c8', # v1
        '00000000-0000-0000-0000-000000000000', # nil UUID
        '550E8400-E29B-41D4-A716-446655440000'  # uppercase OK
      ].each { |uuid| expect(described_class.default_format).to match(uuid) }
    end

    it 'rejects malformed strings' do
      [
        'not-a-uuid',
        '550e8400-e29b-41d4-a716',
        '550e8400e29b41d4a716446655440000',
        '550e8400-e29b-41d4-a716-44665544000Z'
      ].each { |bad| expect(described_class.default_format).not_to match(bad) }
    end
  end

  describe 'integration via the DSL' do
    let(:klass) do
      Class.new(FieldStruct::Base) { required :id, :uuid }
    end

    it 'auto-populates the field options with default_format' do
      expect(klass.metadata[:id].options[:format]).to eq(described_class::DEFAULT_FORMAT)
    end

    it 'accepts a valid UUID' do
      uuid = '550e8400-e29b-41d4-a716-446655440000'
      expect(klass.new(id: uuid)).to be_valid
    end

    it 'records "is invalid" for a malformed UUID' do
      instance = klass.new(id: 'not-a-uuid')
      expect(instance.errors[:id]).to include('is invalid')
    end

    it 'reports "is required" for nil on required fields' do
      expect(klass.new(id: nil).errors[:id]).to include('is required')
    end
  end

  describe 'user-provided format: overrides the default' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        required :short_id, :uuid, format: /\A\h{8}\z/
      end
    end

    it 'uses the user-provided regex' do
      expect(klass.metadata[:short_id].options[:format]).to eq(/\A\h{8}\z/)
    end

    it 'validates against the override, not the default' do
      expect(klass.new(short_id: 'deadbeef')).to be_valid
      expect(klass.new(short_id: '550e8400-e29b-41d4-a716-446655440000').errors[:short_id])
        .to include('is invalid')
    end
  end
end
