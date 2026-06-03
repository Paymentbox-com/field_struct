# frozen_string_literal: true

RSpec.describe FieldStruct::Errors do
  let(:errors) { described_class.new }

  describe 'a fresh errors object' do
    it 'is empty?' do
      expect(errors.empty?).to be true
    end

    it 'returns an empty array for any field key' do
      expect(errors[:name]).to eq([])
    end

    it 'returns an empty hash from to_h and messages' do
      expect(errors.to_h).to eq({})
      expect(errors.messages).to eq({})
    end
  end

  describe 'adding messages' do
    before { errors.add(:name, 'is required') }

    it 'is no longer empty?' do
      expect(errors.empty?).to be false
    end

    it 'exposes the messages via #[]' do
      expect(errors[:name]).to eq(['is required'])
    end

    it 'accepts string-form field names' do
      errors.add('age', 'is required')
      expect(errors['age']).to eq(['is required'])
      expect(errors[:age]).to eq(['is required'])
    end

    it 'collects multiple messages on the same field in order' do
      errors.add(:name, 'is too short')
      expect(errors[:name]).to eq(['is required', 'is too short'])
    end

    it 'surfaces to_h with only fields that have messages' do
      expect(errors.to_h).to eq(name: ['is required'])
    end

    it 'messages mirrors to_h' do
      expect(errors.messages).to eq(errors.to_h)
    end
  end

  describe 'clearing a field' do
    before do
      errors.add(:name, 'is required')
      errors.add(:age, 'is required')
    end

    it 'removes messages for the named field' do
      errors.clear(:name)
      expect(errors[:name]).to eq([])
    end

    it 'leaves other fields intact' do
      errors.clear(:name)
      expect(errors[:age]).to eq(['is required'])
    end

    it 'is empty? when every field has been cleared' do
      errors.clear(:name)
      errors.clear(:age)
      expect(errors.empty?).to be true
    end
  end

  describe '#full_messages' do
    it 'is empty for a fresh errors object' do
      expect(errors.full_messages).to eq([])
    end

    it 'prepends the humanized field name to each message' do
      errors.add(:name, 'is required')
      expect(errors.full_messages).to eq(['Name is required'])
    end

    it 'turns underscores into spaces and upcases only the first character' do
      errors.add(:first_name, 'is required')
      expect(errors.full_messages).to eq(['First name is required'])
    end

    it 'does not downcase the rest of a multi-word field label' do
      errors.add(:api_URL, 'is invalid')
      expect(errors.full_messages).to eq(['Api URL is invalid'])
    end

    it 'renders one entry per message, in field then message order' do
      errors.add(:name, 'is required')
      errors.add(:name, 'is too short')
      errors.add(:age, 'is required')
      expect(errors.full_messages).to eq(
        ['Name is required', 'Name is too short', 'Age is required']
      )
    end

    it 'passes :base messages through unprefixed' do
      errors.add(:base, 'End date must follow start date')
      expect(errors.full_messages).to eq(['End date must follow start date'])
    end

    it 'mixes prefixed field messages with unprefixed :base messages' do
      errors.add(:name, 'is required')
      errors.add(:base, 'is structurally invalid')
      expect(errors.full_messages).to eq(
        ['Name is required', 'is structurally invalid']
      )
    end
  end
end
