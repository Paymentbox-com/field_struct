# frozen_string_literal: true

require 'rbs'

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

    it 'emits a typed reader and a permissive writer per field' do
      klass = struct('User') do
        required :name, :string
        optional :age, :integer
      end

      rbs = described_class.generate(klass)

      expect(rbs).to include('class User < ::FieldStruct::Base')
      expect(rbs).to include('attr_reader name: ::String')
      expect(rbs).to include('def name=: (untyped value) -> untyped')
      expect(rbs).to include('attr_reader age: ::Integer?')
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

    it 'maps the value type to untyped' do
      klass = struct('Bag') { optional :payload, :value }
      expect(described_class.generate(klass)).to include('attr_reader payload: untyped')
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

    it 'produces syntactically valid RBS' do
      klass = struct('Acme::Profile') do
        required :handle, :string
        optional :age, :integer
        required :active, :boolean
        optional :joined_on, :date
      end

      expect { RBS::Parser.parse_signature(described_class.generate(klass)) }
        .not_to raise_error
    end
  end
end
