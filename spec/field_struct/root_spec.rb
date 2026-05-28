# frozen_string_literal: true

require 'pathname'

RSpec.describe 'FieldStruct.root' do
  it 'returns an absolute Pathname' do
    expect(FieldStruct.root).to be_a(Pathname)
    expect(FieldStruct.root).to be_absolute
  end

  it 'points at the directory that contains lib/field_struct.rb' do
    expect(FieldStruct.root.join('lib', 'field_struct.rb')).to exist
    expect(FieldStruct.root.join('lib', 'field_struct', 'version.rb')).to be_file
  end

  it 'resolves to the repository root in development' do
    expect(FieldStruct.root.to_s).to eq(File.expand_path('../..', __dir__))
  end

  it 'memoizes the same object' do
    expect(FieldStruct.root).to equal(FieldStruct.root)
  end
end
