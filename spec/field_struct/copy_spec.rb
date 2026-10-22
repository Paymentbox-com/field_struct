# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'copying (dup / clone)' do
  let(:klass) do
    Class.new(described_class) do
      required :name, :string
    end
  end

  %i[dup clone].each do |copy_method|
    describe "##{copy_method}" do
      it 'gives the copy its own Errors object' do
        original = klass.new(name: 'Alice')
        copy = original.public_send(copy_method)

        expect(copy.errors).not_to equal(original.errors)
      end

      it 'leaves the original valid when the copy is made invalid' do
        original = klass.new(name: 'Alice')
        copy = original.public_send(copy_method)
        copy.name = ''

        expect(copy).not_to be_valid
        expect(original).to be_valid
      end

      it "starts the copy with the original's errors (copied, not shared)" do
        original = klass.new(name: '')
        copy = original.public_send(copy_method)

        expect(copy.errors.to_h).to eq(name: ['is required'])
        copy.errors.add(:name, 'is odd')
        expect(original.errors[:name]).to eq(['is required'])
      end

      it 'does not let the original leak errors into the copy' do
        original = klass.new(name: 'Alice')
        copy = original.public_send(copy_method)
        original.name = ''

        expect(copy).to be_valid
      end
    end
  end

  describe 'frozen instances' do
    let(:frozen_klass) do
      Class.new(described_class) do
        frozen!
        required :name, :string
      end
    end

    it 'clone stays frozen, with its own Errors' do
      original = frozen_klass.new(name: '')
      copy = original.clone

      expect(copy).to be_frozen
      expect(copy.errors).not_to equal(original.errors)
      expect(copy.errors.to_h).to eq(name: ['is required'])
    end

    it 'clone(freeze: false) gives an unfrozen, independently-erroring copy' do
      original = frozen_klass.new(name: 'Alice')
      copy = original.clone(freeze: false)
      copy.name = ''

      expect(copy).not_to be_frozen
      expect(original).to be_valid
    end

    it 'dup gives an unfrozen copy with its own Errors' do
      original = frozen_klass.new(name: 'Alice')
      copy = original.dup

      expect(copy).not_to be_frozen
      expect(copy.errors).not_to equal(original.errors)
    end
  end
end
