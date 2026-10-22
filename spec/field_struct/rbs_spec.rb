# frozen_string_literal: true

# The rbs gem is part of the dev toolchain (Ruby >= 3.2); it's absent on the
# Ruby-floor CI job, where the single grammar-validation example below skips.
begin
  require 'rbs'
rescue LoadError
  nil
end

RSpec.describe FieldStruct::RBS do
  # Build a named FieldStruct subclass without leaking a top-level constant.
  def struct(const_name, &body)
    klass = Class.new(FieldStruct::Base)
    klass.class_eval(&body) if body
    stub_const(const_name, klass)
    klass
  end

  describe '.generate' do
    it 'rejects non-FieldStruct classes' do
      expect { described_class.generate(String) }
        .to raise_error(ArgumentError, /FieldStruct::Base subclass/)
    end

    it 'rejects anonymous classes' do
      anon = Class.new(FieldStruct::Base)
      expect { described_class.generate(anon) }
        .to raise_error(ArgumentError, /anonymous/)
    end

    it 'emits a typed reader and a typed writer per field' do
      klass = struct('User') do
        required :name, :string
        optional :age, :integer
      end

      rbs = described_class.generate(klass)

      expect(rbs).to include('class User < ::FieldStruct::Base')
      expect(rbs).to include('attr_reader name: ::String')
      expect(rbs).to include('attr_reader age: ::Integer?')
    end

    # The runtime setter accepts nil and returns the coerced value (or nil),
    # whether or not the field is required — so the writer is (T?) -> T?.
    it 'types every writer as (T? value) -> T?, required or not' do
      klass = struct('Member') do
        required :name, :string
        optional :age, :integer
        required :active, :boolean
      end

      rbs = described_class.generate(klass)

      expect(rbs).to include('def name=: (::String? value) -> ::String?')
      expect(rbs).to include('def age=: (::Integer? value) -> ::Integer?')
      expect(rbs).to include('def active=: (bool? value) -> bool?')
    end

    it 'starts with a header stating that the types describe a valid instance' do
      klass = struct('Note') { required :body, :string }
      header = described_class.generate(klass).lines.take_while { |line| line.start_with?('#') }.join

      expect(header).to match(/valid instance/)
      expect(header).to match(/keep_raw/)
    end

    it 'makes required fields non-nullable and optional fields nullable' do
      klass = struct('Account') do
        required :id, :string
        optional :nickname, :string
      end

      rbs = described_class.generate(klass)

      expect(rbs).to include('attr_reader id: ::String')
      expect(rbs).to include('attr_reader nickname: ::String?')
    end

    it 'maps boolean to bool' do
      klass = struct('Flag') { required :active, :boolean }
      expect(described_class.generate(klass)).to include('attr_reader active: bool')
    end

    it 'maps the value type to an untyped reader and writer, never untyped?' do
      klass = struct('Bag') { optional :payload, :value }
      rbs = described_class.generate(klass)

      expect(rbs).to include('attr_reader payload: untyped')
      expect(rbs).to include('def payload=: (untyped value) -> untyped')
      expect(rbs).not_to include('untyped?')
    end

    it 'maps stdlib scalar types to their qualified Ruby types' do
      klass = struct('Event') do
        required :on, :date
        optional :at, :time
        optional :amount, :big_decimal
      end

      rbs = described_class.generate(klass)

      expect(rbs).to include('attr_reader on: ::Date')
      expect(rbs).to include('attr_reader at: ::Time?')
      expect(rbs).to include('attr_reader amount: ::BigDecimal?')
    end

    it 'parametrizes array fields with their element type' do
      klass = struct('Post') { optional :tags, :array, of: :string }
      expect(described_class.generate(klass)).to include('attr_reader tags: ::Array[::String]?')
    end

    it 'emits union members joined with |' do
      klass = struct('Token') { required :value, :union, of: %i[string integer] }
      expect(described_class.generate(klass)).to include('attr_reader value: (::String | ::Integer)')
    end

    it 'renders a boolean union member as bool' do
      klass = struct('Toggle') { required :state, :union, of: %i[string boolean] }
      expect(described_class.generate(klass)).to include('attr_reader state: (::String | bool)')
    end

    it 'collapses a union with a :value member to untyped' do
      klass = struct('Loose') { optional :thing, :union, of: %i[integer value] }
      expect(described_class.generate(klass)).to include('attr_reader thing: untyped')
    end

    it 'references nested FieldStruct types by qualified name' do
      address = struct('Address') { required :city, :string }
      klass = struct('Person') { optional :address, address }
      expect(described_class.generate(klass)).to include('attr_reader address: ::Address?')
    end

    it 'parametrizes arrays of nested structs' do
      line = struct('LineItem') { required :sku, :string }
      klass = struct('Order') { optional :items, :array, of: line }
      expect(described_class.generate(klass)).to include('attr_reader items: ::Array[::LineItem]?')
    end

    it 'fills type arguments for a custom type whose ruby_type is a bare generic class' do
      hash_type = Class.new(FieldStruct::Types::Base) do
        def coerce(value, **) = value
        def ruby_type = Hash
      end
      klass = struct('Envelope') { optional :meta, hash_type }

      expect(described_class.generate(klass)).to include('attr_reader meta: ::Hash[untyped, untyped]?')
    end

    it "uses a custom type's rbs_type when it declares one" do
      hash_type = Class.new(FieldStruct::Types::Base) do
        def coerce(value, **) = value
        def ruby_type = Hash
        def rbs_type = '::Hash[::Symbol, ::Integer]'
      end
      klass = struct('Counts') { required :by_name, hash_type }
      rbs = described_class.generate(klass)

      expect(rbs).to include('attr_reader by_name: ::Hash[::Symbol, ::Integer]')
      expect(rbs).to include('def by_name=: (::Hash[::Symbol, ::Integer]? value) -> ::Hash[::Symbol, ::Integer]?')
    end

    it 'wraps namespaced classes in their module nesting' do
      klass = struct('Acme::Widget') { required :name, :string }
      rbs = described_class.generate(klass)

      expect(rbs).to include('module Acme')
      expect(rbs).to include('  class Widget < ::FieldStruct::Base')
      expect(rbs).to match(/^end\n?\z/)
    end

    it 'emits only own fields for subclasses and inherits the parent type' do
      parent = struct('Animal') { required :name, :string }
      child = Class.new(parent) { required :breed, :string }
      stub_const('Dog', child)

      rbs = described_class.generate(child)

      expect(rbs).to include('class Dog < ::Animal')
      expect(rbs).to include('attr_reader breed: ::String')
      expect(rbs).not_to include('name:')
    end

    # Parsing alone accepts a bare ::Hash or an unknown constant; building
    # each class's definitions in an environment that also loads the gem's
    # own sig/ and validating every type in them (what `rbs validate` does)
    # does not.
    it 'produces RBS whose definitions build and validate against the gem sigs' do
      skip 'rbs gem not installed (Ruby-floor job)' unless defined?(RBS::DefinitionBuilder)

      hash_type = Class.new(FieldStruct::Types::Base) do
        def coerce(value, **) = value
        def ruby_type = Hash
      end
      address = struct('Acme::Address') { required :city, :string }
      line = struct('Acme::LineItem') { required :sku, :string }
      profile = struct('Acme::Profile') do
        required :handle, :string
        optional :age, :integer
        required :active, :boolean
        optional :joined_on, :date
        optional :at, :time
        optional :amount, :big_decimal
        optional :address, address
        optional :items, :array, of: line
        optional :tags, :array, of: :string
        optional :token, :union, of: [:string, :integer, address]
        optional :payload, :value
        optional :meta, hash_type
        optional :scope, :value, rbs_type: '::Hash[::Symbol, ::Integer] | ::Array[::String]'
      end

      source = [address, line, profile].map { |klass| described_class.generate(klass) }.join("\n")

      expect(rbs_validation_errors(source, %w[::Acme::Address ::Acme::LineItem ::Acme::Profile])).to eq([])
    end
  end

  describe '.type_for' do
    let(:klass) do
      struct('Shipment') do
        required :id, :string
        optional :weight, :big_decimal
        optional :parcels, :array, of: :integer
        optional :scope, :value, rbs_type: '::ActiveRecord::Relation'
      end
    end

    it "returns a field's RBS type, nullable when the field is optional" do
      expect(described_class.type_for(klass.metadata[:id])).to eq('::String')
      expect(described_class.type_for(klass.metadata[:weight])).to eq('::BigDecimal?')
      expect(described_class.type_for(klass.metadata[:parcels])).to eq('::Array[::Integer]?')
    end

    it 'returns the bare type with nullable: false' do
      expect(described_class.type_for(klass.metadata[:weight], nullable: false)).to eq('::BigDecimal')
    end

    it 'returns the nullable type with nullable: true, even for a required field' do
      expect(described_class.type_for(klass.metadata[:id], nullable: true)).to eq('::String?')
    end

    it "honours the field's rbs_type override" do
      expect(described_class.type_for(klass.metadata[:scope], nullable: false)).to eq('::ActiveRecord::Relation')
      expect(described_class.type_for(klass.metadata[:scope])).to eq('::ActiveRecord::Relation?')
    end

    it 'rejects anything but a Field' do
      expect { described_class.type_for(:id) }
        .to raise_error(ArgumentError, /expects a FieldStruct::Field.*got :id/)
    end
  end

  describe 'the rbs_type: field option' do
    it 'is emitted verbatim for the reader and the writer' do
      klass = struct('Report') do
        required :scope, :value, rbs_type: '::ActiveRecord::Relation'
      end
      rbs = described_class.generate(klass)

      expect(rbs).to include('attr_reader scope: ::ActiveRecord::Relation')
      expect(rbs).to include('def scope=: (::ActiveRecord::Relation? value) -> ::ActiveRecord::Relation?')
    end

    it 'is parenthesized before ? when it is a union' do
      klass = struct('Either') { optional :id, :value, rbs_type: '::String | ::Integer' }
      expect(described_class.generate(klass)).to include('attr_reader id: (::String | ::Integer)?')
    end

    it 'is kept off the coercion options and readable on the Field' do
      klass = struct('Scoped') { optional :scope, :value, rbs_type: '::Object' }
      field = klass.metadata[:scope]

      expect(field.rbs_type).to eq('::Object')
      expect(field.options).not_to have_key(:rbs_type)
      expect(field.inspect).to include('rbs_type="::Object"')
    end

    it 'defaults to nil' do
      klass = struct('Plain') { optional :name, :string }
      expect(klass.metadata[:name].rbs_type).to be_nil
    end

    it 'must be a non-empty String' do
      expect { struct('Bad1') { optional :scope, :value, rbs_type: :Relation } }
        .to raise_error(ArgumentError, /rbs_type: must be a non-empty String of RBS.*got :Relation/)
      expect { struct('Bad2') { optional :scope, :value, rbs_type: ' ' } }
        .to raise_error(ArgumentError, /rbs_type: must be a non-empty String of RBS/)
    end
  end

  # @param source [String] generated RBS
  # @param class_names [Array<String>] absolute names of the generated classes
  # @return [Array<String>] every error from building and validating them
  def rbs_validation_errors(source, class_names)
    loader = RBS::EnvironmentLoader.new
    %w[date time bigdecimal].each { |lib| loader.add(library: lib, version: nil) }
    loader.add(path: Pathname(File.expand_path('../../sig', __dir__)))
    env = RBS::Environment.from_loader(loader)
    buffer = RBS::Buffer.new(name: 'generated.rbs', content: source)
    _, directives, decls = RBS::Parser.parse_signature(buffer)
    env.add_signature(buffer: buffer, directives: directives, decls: decls)
    env = env.resolve_type_names
    builder = RBS::DefinitionBuilder.new(env: env)
    validator = RBS::Validator.new(env: env)

    class_names.flat_map do |name|
      type_name = RBS::TypeName.parse(name)
      [builder.build_instance(type_name), builder.build_singleton(type_name)].flat_map do |definition|
        errors = []
        definition.each_type do |type|
          validator.validate_type(type, context: nil)
        rescue RBS::BaseError => e
          errors << e.message
        end
        errors
      end
    rescue RBS::BaseError => e
      [e.message]
    end
  end
end
