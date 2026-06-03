# frozen_string_literal: true

# Human/agent-readable schema summary: fields, types, required-ness, and the
# native options each field's type accepts (design invariant 7 — "what can I
# put here" in one call). See FieldStruct::Base.describe / Metadata#describe.
RSpec.describe 'FieldStruct::Base.describe' do
  let(:klass) do
    Class.new(FieldStruct::Base) do
      required :name, :string
      optional :age, :integer
      required :tags, :array, of: :string
    end
  end

  it 'starts with the class name as a header' do
    stub_const('Person', klass)
    expect(Person.describe).to start_with("Person\n")
  end

  it 'falls back to a placeholder name for anonymous classes' do
    expect(klass.describe).to start_with('AnonymousFieldStruct')
  end

  it 'lists each field with its type and required-ness' do
    out = klass.describe
    expect(out).to include('name (String, required)')
    expect(out).to include('age (Integer, optional)')
  end

  it 'shows the accepted native options for each field type' do
    out = klass.describe
    expect(out).to match(/name .*accepts.*format.*enum/)
    expect(out).to match(/age .*accepts.*in /)
  end

  it 'marks required options with a star (array of:)' do
    expect(klass.describe).to match(/tags .*of\* /)
  end

  it 'lists a type option preset names when present' do
    uuid_klass = Class.new(FieldStruct::Base) { required :id, :uuid }
    expect(uuid_klass.describe).to match(/presets:.*v4/)
  end

  describe 'Metadata#describe' do
    it 'returns the field lines without the class header' do
      body = klass.metadata.describe
      expect(body).to include('name (String, required)')
      expect(body).not_to include('AnonymousFieldStruct')
    end

    it 'handles a class with no fields' do
      empty = Class.new(FieldStruct::Base)
      expect(empty.metadata.describe).to eq('(no fields)')
    end
  end
end
