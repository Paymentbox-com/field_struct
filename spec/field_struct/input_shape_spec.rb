# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'input shape' do
  let(:klass) do
    Class.new(described_class) do
      def self.name = 'Person'

      optional :name, :string
    end
  end

  # Stands in for ActionController::Parameters and other Hash-likes: not a
  # Hash, but convertible to one via #to_hash.
  let(:hash_like) do
    Class.new do
      def initialize(hash)
        @hash = hash
      end

      def to_hash
        @hash.dup
      end
    end
  end

  describe '.new' do
    it 'accepts no argument' do
      expect(klass.new.name).to be_nil
    end

    it 'treats nil as no input' do
      expect(klass.new(nil).name).to be_nil
    end

    it 'accepts an object responding to #to_hash' do
      expect(klass.new(hash_like.new('name' => 'Alice')).name).to eq('Alice')
    end

    [[], 'name', 5, :name].each do |input|
      it "refuses #{input.class} input with an ArgumentError naming the class" do
        expect { klass.new(input) }
          .to raise_error(ArgumentError, "Person.new expects a Hash (or an object responding to #to_hash), got #{input.class}")
      end
    end

    it 'does not echo the raw input in the message' do
      expect { klass.new('secret-value') }.to raise_error(ArgumentError) { |e| expect(e.message).not_to include('secret-value') }
    end
  end

  describe '#assign_attributes' do
    it 'accepts an object responding to #to_hash' do
      instance = klass.new
      instance.assign_attributes(hash_like.new(name: 'Bob'))
      expect(instance.name).to eq('Bob')
    end

    [nil, [], 'name', 5].each do |input|
      it "refuses #{input.class} input with an ArgumentError naming the class" do
        expect { klass.new.assign_attributes(input) }
          .to raise_error(ArgumentError, "Person#assign_attributes expects a Hash (or an object responding to #to_hash), got #{input.class}")
      end
    end
  end
end
