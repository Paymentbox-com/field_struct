# frozen_string_literal: true

RSpec.describe 'FieldStruct::Metadata#to_h (schema view)' do
  def struct(const_name, &body)
    klass = Class.new(FieldStruct::Base)
    klass.class_eval(&body) if body
    stub_const(const_name, klass)
    klass
  end

  it 'still yields to a block (Enumerable#to_h is preserved)' do
    klass = struct('Blockish') { required :a, :string }
    pairs = klass.metadata.to_h { |field| [field.name, field.required?] }
    expect(pairs).to eq(a: true)
  end

  it 'keeps Base#attributes working (regression for the block form)' do
    klass = struct('Reg') { required :a, :string }
    expect(klass.new(a: 'x').attributes).to eq(a: 'x')
  end

  it 'returns a copy-pasteable schema hash when called without a block' do
    klass = struct('Person') do
      required :name, :string
      optional :age, :integer, default: 0
      optional :email, :email, desc: 'contact'
    end

    expect(klass.metadata.to_h).to eq(
      name: {type: 'String', ruby_type: 'String', required: true, default: nil, options: {}, description: nil},
      age: {type: 'Integer', ruby_type: 'Integer', required: false, default: 0, options: {}, description: nil},
      email: {type: 'Email', ruby_type: 'String', required: false, default: nil,
              options: {format: FieldStruct::Types::Email.default_format}, description: 'contact'}
    )
  end

  it 'renders boolean ruby_type as a union string' do
    klass = struct('Flag') { required :on, :boolean }
    expect(klass.metadata.to_h[:on][:ruby_type]).to eq('TrueClass | FalseClass')
  end

  it 'sanitizes array of_type to a readable class name' do
    klass = struct('Post') { optional :tags, :array, of: :string }
    expect(klass.metadata.to_h[:tags]).to include(type: 'Array', ruby_type: 'Array', options: {of_type: 'String'})
  end

  it 'references nested struct ruby_type by qualified name' do
    addr = struct('Addr') { required :city, :string }
    klass = struct('Loc') { optional :addr, addr }
    expect(klass.metadata.to_h[:addr][:ruby_type]).to eq('Addr')
  end

  it 'renders a callable default as a placeholder, not an object ref' do
    klass = struct('Token') { optional :id, :string, default: -> { 'x' } }
    expect(klass.metadata.to_h[:id][:default]).to eq('<callable>')
  end
end
