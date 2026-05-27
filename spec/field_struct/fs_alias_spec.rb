# frozen_string_literal: true

require 'pp'

RSpec.describe FieldStruct, '.use_alias!' do
  # Always restore the default state before *and* after each example,
  # in case a prior spec set @short_alias or const_set ::FS.
  around do |ex|
    saved_alias = FieldStruct.instance_variable_get(:@short_alias)
    had_fs = Object.const_defined?(:FS, false)
    fs_value = had_fs ? Object.const_get(:FS) : nil

    FieldStruct.instance_variable_set(:@short_alias, nil)
    Object.send(:remove_const, :FS) if Object.const_defined?(:FS, false)

    ex.run
  ensure
    FieldStruct.instance_variable_set(:@short_alias, saved_alias)
    Object.send(:remove_const, :FS) if Object.const_defined?(:FS, false)
    Object.const_set(:FS, fs_value) if had_fs
  end

  describe 'default behavior (no alias)' do
    it 'inspect outputs the full FieldStruct prefix' do
      expect(FieldStruct::Errors.new.inspect).to eq('#<FieldStruct::Errors empty>')
    end

    it 'does not define a top-level FS constant' do
      expect(Object.const_defined?(:FS, false)).to be false
    end
  end

  describe '.use_alias! (default :FS)' do
    it 'defines a top-level FS constant pointing to FieldStruct' do
      FieldStruct.use_alias!
      expect(FS).to be(FieldStruct)
    end

    it 'returns FieldStruct (chainable)' do
      expect(FieldStruct.use_alias!).to be(FieldStruct)
    end

    it 'switches inspect output to use the short prefix' do
      FieldStruct.use_alias!
      expect(FieldStruct::Errors.new.inspect).to eq('#<FS::Errors empty>')
    end

    it 'is idempotent — calling twice does nothing surprising' do
      FieldStruct.use_alias!
      expect { FieldStruct.use_alias! }.not_to raise_error
      expect(FS).to be(FieldStruct)
    end

    it 'raises if the chosen constant is already defined to something else' do
      Object.const_set(:FS, Module.new)
      expect { FieldStruct.use_alias! }.to raise_error(NameError, /already defined/)
    end
  end

  describe '.use_alias! with a custom name' do
    around do |ex|
      had_fields = Object.const_defined?(:Fields, false)
      ex.run
    ensure
      Object.send(:remove_const, :Fields) if Object.const_defined?(:Fields, false) && !had_fields
    end

    it 'sets up the custom constant and uses it as the inspect prefix' do
      FieldStruct.use_alias!(:Fields)
      expect(Fields).to be(FieldStruct)
      expect(FieldStruct::Errors.new.inspect).to eq('#<Fields::Errors empty>')
    end
  end

  describe 'inspect prefix threading across surface objects' do
    let(:klass) do
      Class.new(FieldStruct::Base) do
        required :name, :string
        optional :age, :integer
      end
    end

    before { FieldStruct.use_alias! }

    it 'Field inspect uses the short prefix' do
      expect(klass.metadata[:name].inspect).to start_with('#<FS::Field')
    end

    it 'Metadata one-line inspect uses the short prefix' do
      expect(klass.metadata.inspect).to start_with('#<FS::Metadata')
    end

    it 'Types::Base instance inspect uses the short prefix' do
      expect(FieldStruct::Types::String.new.inspect).to eq('#<FS::Types::String>')
    end

    it 'Nested instance inspect uses the short prefix' do
      addr = Class.new(FieldStruct::Base) { required :s, :string }
      stub_const('FSAliasAddr', addr)
      t = FieldStruct::Types::Nested.new(addr)
      expect(t.inspect).to eq('#<FS::Types::Nested struct_class=FSAliasAddr>')
    end

    it 'Union instance inspect uses the short prefix' do
      t = FieldStruct::Types::Union.new([FieldStruct::Types::String.new, FieldStruct::Types::Integer.new])
      expect(t.inspect).to eq('#<FS::Types::Union of=String | Integer>')
    end

    it 'Registry inspect uses the short prefix' do
      reg = FieldStruct::Registry.new
      reg.register(:string, FieldStruct::Types::String)
      expect(reg.inspect).to eq('#<FS::Registry types=[:string]>')
    end

    it 'instance inspect (Base#inspect) uses the short prefix on AnonymousFieldStruct' do
      anon_klass = Class.new(FieldStruct::Base) { required :n, :string }
      inst = anon_klass.new(n: 'x')
      expect(inst.inspect).to start_with('#<AnonymousFieldStruct ') # named-class branch unchanged
      # explicitly: named classes keep their own class name, the alias
      # is only used for FieldStruct-namespace classes
    end
  end
end

RSpec.describe FieldStruct::Metadata, '#pretty_print closing >' do
  it 'puts the closing > on its own line' do
    klass = Class.new(FieldStruct::Base) do
      required :name, :string
      optional :age, :integer
    end
    out = klass.metadata.pretty_inspect
    expect(out).to match(/\n>\n?\z/)
  end
end
