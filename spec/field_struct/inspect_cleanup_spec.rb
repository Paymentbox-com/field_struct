# frozen_string_literal: true

require 'pp' # for #pretty_inspect

RSpec.describe 'inspect cleanup across surface objects' do
  describe FieldStruct::Metadata do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        required :name, :string
        optional :age, :integer, default: 0
      end
    end

    it 'has a one-line inspect with the field-name list' do
      expect(klass.metadata.inspect).to eq('#<FieldStruct::Metadata fields=[:name, :age]>')
    end

    it 'pretty_print fans out one field per line' do
      out = klass.metadata.pretty_inspect
      expect(out).to include('#<FieldStruct::Metadata')
      expect(out).to include(':name String required')
      expect(out).to include(':age Integer default=0')
    end

    it 'does not dump @fields / @serializations via reflection' do
      expect(klass.metadata.inspect).not_to include('@fields=')
      expect(klass.metadata.inspect).not_to include('@serializations=')
    end

    it 'shows serializations when present' do
      sub = Class.new(klass) { serialize :json, name: 'fullName' }
      expect(sub.metadata.inspect).to include('serializations=[:json]')
    end

    it 'reports empty Metadata cleanly' do
      empty = Class.new(FieldStruct::Base)
      expect(empty.metadata.inspect).to eq('#<FieldStruct::Metadata empty>')
    end
  end

  describe FieldStruct::Types::Base do
    it 'a bare-vanilla type instance shows just the class name' do
      expect(FieldStruct::Types::String.new.inspect).to eq('#<FieldStruct::Types::String>')
    end

    it 'does not dump ivars' do
      expect(FieldStruct::Types::Integer.new.inspect).not_to include('@')
    end

    describe FieldStruct::Types::Nested do
      let(:addr) do
        addr = Class.new(FieldStruct::Base) { required :street, :string }
        stub_const('InspCleanupAddress', addr)
        addr
      end

      it 'shows the wrapped struct class name' do
        t = FieldStruct::Types::Nested.new(addr)
        expect(t.inspect).to eq('#<FieldStruct::Types::Nested struct_class=InspCleanupAddress>')
      end

      it 'falls back to AnonymousFieldStruct for unnamed struct classes' do
        anon = Class.new(FieldStruct::Base) { required :x, :string }
        t = FieldStruct::Types::Nested.new(anon)
        expect(t.inspect).to include('AnonymousFieldStruct')
      end
    end

    describe FieldStruct::Types::Union do
      it 'lists member type basenames separated by |' do
        t = FieldStruct::Types::Union.new([FieldStruct::Types::String.new, FieldStruct::Types::Integer.new])
        expect(t.inspect).to eq('#<FieldStruct::Types::Union of=String | Integer>')
      end
    end
  end

  describe FieldStruct::Errors do
    it 'reports empty errors cleanly' do
      expect(FieldStruct::Errors.new.inspect).to eq('#<FieldStruct::Errors empty>')
    end

    it 'shows field => messages when non-empty' do
      errs = FieldStruct::Errors.new
      errs.add(:name, "can't be blank")
      expect(errs.inspect).to eq(%(#<FieldStruct::Errors name=["can't be blank"]>))
    end
  end

  describe FieldStruct::Registry do
    it 'lists registered names' do
      reg = FieldStruct::Registry.new
      reg.register(:string, FieldStruct::Types::String)
      reg.register(:integer, FieldStruct::Types::Integer)
      expect(reg.inspect).to eq('#<FieldStruct::Registry types=[:string, :integer]>')
    end

    it 'marks parent presence' do
      child = FieldStruct::Registry.new(FieldStruct.types)
      child.register(:money, FieldStruct::Types::BigDecimal)
      expect(child.inspect).to include('parent')
    end
  end

  describe '#field / #required / #optional return value' do
    let(:klass) { Class.new(FieldStruct::Base) }

    it '#field returns the class Metadata' do
      result = klass.field(:name, :string)
      expect(result).to be(klass.metadata)
    end

    it '#required returns the class Metadata' do
      result = klass.required(:name, :string)
      expect(result).to be(klass.metadata)
    end

    it '#optional returns the class Metadata' do
      result = klass.optional(:age, :integer)
      expect(result).to be(klass.metadata)
    end

    it 'still adds the field to metadata' do
      klass.required(:email, :string)
      expect(klass.metadata[:email]).to be_a(FieldStruct::Field)
    end
  end
end
