# frozen_string_literal: true

begin
  require 'rbs'
rescue LoadError
  nil
end

# The committed sig must admit nil wherever the runtime really returns it.
# Each example proves the nil at runtime, then reads the declared type out of
# sig/field_struct.rbs.
RSpec.describe 'sig/field_struct.rbs nullability' do
  before { skip 'rbs gem not installed (ActiveSupport lane)' unless defined?(RBS::Parser) }

  let(:struct) do
    Class.new(FieldStruct::Base) do
      optional :name, :string
      optional :on, :date, format: nil
    end
  end

  # @param class_name [String] e.g. "FieldStruct::Base"
  # @param member [String] method or attribute name
  # @return [String] the declared return type
  def sig_type(class_name, member)
    _, _, decls = RBS::Parser.parse_signature(File.read(File.expand_path('../sig/field_struct.rbs', __dir__)))
    path = class_name.split('::')
    decl = path.reduce(decls) do |scope, name|
      scope.find { |d| d.respond_to?(:name) && d.name.name.to_s == name }.then { |d| d.respond_to?(:members) ? d.members : d }
    end
    found = decl.find { |m| m.respond_to?(:name) && m.name.to_s == member }
    found.is_a?(RBS::AST::Members::MethodDefinition) ? found.overloads.first.method_type.type.return_type.to_s : found.type.to_s
  end

  it 'types Base#attributes, #to_h and #as_json values as nullable' do
    expect(struct.new.attributes.values).to include(nil)
    expect(struct.new.as_json.values).to include(nil)

    %w[attributes to_h as_json].each do |method|
      expect(sig_type('FieldStruct::Base', method)).to eq('::Hash[Symbol, Object?]')
    end
  end

  it 'types the pattern-matching protocol values as nullable' do
    expect(struct.new.deconstruct).to include(nil)
    expect(sig_type('FieldStruct::Base', 'deconstruct')).to eq('::Array[Object?]')
    expect(sig_type('FieldStruct::Base', 'deconstruct_keys')).to eq('::Hash[Symbol, Object?]')
  end

  it 'types Field#options values as nullable' do
    expect(struct.metadata[:on].options).to eq(format: nil)
    expect(sig_type('FieldStruct::Field', 'options')).to eq('::Hash[Symbol, Object?]')
  end

  it 'types Metadata#to_h schema values as nullable' do
    expect(struct.metadata.to_h[:name].values).to include(nil)
    expect(sig_type('FieldStruct::Metadata', 'to_h')).to eq('::Hash[Symbol, ::Hash[Symbol, Object?]]')
  end
end
