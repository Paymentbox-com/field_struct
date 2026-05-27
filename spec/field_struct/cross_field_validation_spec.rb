# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'cross-field validation' do
  describe 'block form' do
    let(:klass) do
      Class.new(described_class) do
        required :start_date, :date
        required :end_date, :date

        validate do |record|
          if record.start_date && record.end_date && record.start_date > record.end_date
            record.errors.add(:base, 'end_date must not precede start_date')
          end
        end
      end
    end

    context 'when the block condition is satisfied' do
      it 'leaves the record valid' do
        instance = klass.new(start_date: '2024-01-01', end_date: '2024-01-15')
        expect(instance).to be_valid
      end
    end

    context 'when the block condition fires' do
      it 'records the message at errors[:base] and is invalid' do
        instance = klass.new(start_date: '2024-02-01', end_date: '2024-01-15')
        expect(instance).to be_invalid
        expect(instance.errors[:base]).to include(/end_date must not precede/)
      end
    end
  end

  describe 'symbol form' do
    let(:klass) do
      Class.new(described_class) do
        required :password, :string
        required :password_confirmation, :string

        validate :passwords_match

        def passwords_match
          return if password == password_confirmation

          errors.add(:base, 'passwords do not match')
        end
      end
    end

    it 'invokes the named instance method' do
      mismatched = klass.new(password: 'abc', password_confirmation: 'xyz')
      expect(mismatched).to be_invalid
      expect(mismatched.errors[:base]).to include('passwords do not match')
    end

    it 'leaves a matching record valid' do
      matched = klass.new(password: 'abc', password_confirmation: 'abc')
      expect(matched).to be_valid
    end
  end

  describe 'multiple validators' do
    let(:klass) do
      Class.new(described_class) do
        required :a, :integer
        required :b, :integer
        required :c, :integer

        validate :a_must_be_positive
        validate do |record|
          record.errors.add(:base, 'b must equal 2') unless record.b == 2
        end
        validate :c_must_match_a_plus_b

        def a_must_be_positive
          errors.add(:base, 'a must be positive') unless a&.positive?
        end

        def c_must_match_a_plus_b
          return if c == a + b

          errors.add(:base, 'c must equal a + b')
        end
      end
    end

    it 'runs each validator in declaration order' do
      instance = klass.new(a: -1, b: 99, c: 0)
      expect(instance.errors[:base]).to eq([
        'a must be positive',
        'b must equal 2',
        'c must equal a + b'
      ])
    end

    it 'only fires the failing ones; passes if all conditions hold' do
      instance = klass.new(a: 1, b: 2, c: 3)
      expect(instance).to be_valid
    end
  end

  describe 'errors[:base] clears between valid? calls' do
    let(:klass) do
      Class.new(described_class) do
        required :n, :integer

        validate do |record|
          record.errors.add(:base, 'n must be 1') unless record.n == 1
        end
      end
    end

    it 'a stale :base error is dropped when the record becomes valid' do
      instance = klass.new(n: 2)
      expect(instance.errors[:base]).not_to be_empty
      instance.n = 1
      expect(instance).to be_valid # triggers re-validation
      expect(instance.errors[:base]).to be_empty
    end
  end

  describe 'multiple symbols in one validate call' do
    let(:klass) do
      Class.new(described_class) do
        optional :x, :integer

        validate :first_check, :second_check

        def first_check
          errors.add(:base, 'first failed') if x == 1
        end

        def second_check
          errors.add(:base, 'second failed') if x == 1
        end
      end
    end

    it 'registers each as its own validator' do
      instance = klass.new(x: 1)
      expect(instance.errors[:base]).to eq(['first failed', 'second failed'])
    end
  end

  describe 'classes without any validate declaration' do
    let(:klass) do
      Class.new(described_class) { optional :name, :string }
    end

    it 'still works and stays a cheap errors.empty? check' do
      expect(klass.new(name: 'A')).to be_valid
    end

    it 'reports an empty validators list' do
      expect(klass.validators).to eq([])
    end
  end

  describe 'subclass inheritance' do
    let(:parent) do
      Class.new(described_class) do
        required :name, :string

        validate do |record|
          record.errors.add(:base, 'name must be Alice') unless record.name == 'Alice'
        end
      end
    end

    it 'inherits the parent validator' do
      child = Class.new(parent)
      expect(child.new(name: 'Bob')).to be_invalid
    end

    it 'lets the child add its own validators without affecting the parent' do
      child = Class.new(parent) do
        validate do |record|
          record.errors.add(:base, 'extra rule fired')
        end
      end

      child_count = child.validators.size
      parent_count = parent.validators.size
      expect(child_count).to eq(parent_count + 1)
      expect(parent.new(name: 'Alice')).to be_valid
    end
  end

  describe 'interaction with per-field validation' do
    let(:klass) do
      Class.new(described_class) do
        required :a, :integer
        optional :b, :integer

        validate do |record|
          record.errors.add(:base, 'b is required when a > 10') if record.a && record.a > 10 && record.b.nil?
        end
      end
    end

    it 'per-field errors are not cleared by valid?' do
      instance = klass.new(a: nil, b: 0)
      expect(instance.errors[:a]).to include('is required')
      instance.valid? # triggers cross-field run
      expect(instance.errors[:a]).to include('is required') # still there
    end

    it 'cross-field error fires alongside a per-field error' do
      instance = klass.new(a: 11, b: nil)
      expect(instance.errors[:base]).to include(/b is required/)
      expect(instance).to be_invalid
    end
  end
end
