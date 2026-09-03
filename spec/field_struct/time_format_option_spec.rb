# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'format: option on time-shaped types' do
  describe ':date with an explicit format String' do
    let(:klass) do
      Class.new(described_class) do
        required :on, :date, format: '%m/%d/%Y'
      end
    end

    it 'parses input via strptime' do
      expect(klass.new(on: '01/15/2024').on).to eq(Date.new(2024, 1, 15))
    end

    it 'serializes via strftime in as_json' do
      instance = klass.new(on: '01/15/2024')
      expect(instance.as_json[:on]).to eq('01/15/2024')
    end

    it 'round-trips via to_json / from_json' do
      original = klass.new(on: '01/15/2024')
      restored = klass.from_json(original.to_json)
      expect(restored).to eq(original)
    end
  end

  describe ':date with a Symbol preset' do
    let(:klass) do
      Class.new(described_class) do
        required :on, :date, format: :us
      end
    end

    # The declared value is kept as the user wrote it. It used to be overwritten
    # with the strftime String it expands to, which threw away the one piece of
    # information a doc generator actually wants: that this field is `:us`, not
    # some anonymous slash-separated format. Reverse-mapping the String back to
    # a name worked only as long as no two presets shared a value — luck, not a
    # contract.
    it 'keeps the declared preset name rather than overwriting it' do
      expect(klass.metadata[:on].options[:format]).to eq(:us)
    end

    it 'reports the preset name through to_h, where a generator can read it' do
      expect(klass.metadata.to_h[:on][:options][:format]).to eq(:us)
    end

    it 'parses and serializes via the preset format' do
      instance = klass.new(on: '01/15/2024')
      expect(instance.on).to eq(Date.new(2024, 1, 15))
      expect(instance.as_json[:on]).to eq('01/15/2024')
    end
  end

  describe ':datetime with format' do
    let(:klass) do
      Class.new(described_class) do
        required :at, :datetime, format: '%Y-%m-%d %H:%M:%S'
      end
    end

    it 'parses + serializes via the configured format' do
      instance = klass.new(at: '2024-01-15 12:30:45')
      expect(instance.at).to be_a(DateTime)
      expect(instance.as_json[:at]).to eq('2024-01-15 12:30:45')
    end
  end

  describe 'an unknown preset name' do
    it 'still raises at declaration time, not at first use' do
      expect do
        Class.new(FieldStruct::Base) { required :on, :date, format: :klingon }
      end.to raise_error(ArgumentError, /unknown time format preset :klingon/)
    end
  end

  describe ':datetime with the :db preset' do
    let(:klass) do
      Class.new(described_class) do
        required :at, :datetime, format: :db
      end
    end

    it 'keeps the declared preset name' do
      expect(klass.metadata[:at].options[:format]).to eq(:db)
    end

    it 'round-trips DB-format strings' do
      instance = klass.new(at: '2024-01-15 12:30:45')
      restored = klass.from_json(instance.to_json)
      expect(restored).to eq(instance)
    end
  end

  describe ':time with format' do
    let(:klass) do
      Class.new(described_class) do
        required :at, :time, format: '%Y-%m-%d %H:%M:%S'
      end
    end

    it 'parses + serializes via the configured format' do
      instance = klass.new(at: '2024-01-15 12:30:45')
      expect(instance.at).to be_a(Time)
      expect(instance.as_json[:at]).to eq('2024-01-15 12:30:45')
    end
  end

  describe 'no format set — default ISO-8601 behavior' do
    let(:klass) do
      Class.new(described_class) do
        required :on, :date
      end
    end

    it 'parses ISO-8601 input via Date.parse' do
      expect(klass.new(on: '2024-01-15').on).to eq(Date.new(2024, 1, 15))
    end

    it 'serializes as ISO-8601 in as_json' do
      expect(klass.new(on: '2024-01-15').as_json[:on]).to eq('2024-01-15')
    end
  end

  describe 'unknown preset name' do
    it 'raises ArgumentError at class load' do
      expect do
        Class.new(described_class) do
          required :on, :date, format: :nope
        end
      end.to raise_error(ArgumentError, /unknown time format preset/)
    end
  end

  describe 'format: with a Date/DateTime/Time value already (non-string)' do
    let(:klass) do
      Class.new(described_class) do
        required :on, :date, format: '%m/%d/%Y'
      end
    end

    it 'passes the Date through unchanged when given a Date instance' do
      d = Date.new(2024, 1, 15)
      expect(klass.new(on: d).on).to equal(d)
    end
  end

  describe 'subclass-level default_format override' do
    it 'a Date subclass with its own default_format works without explicit format:' do
      us_date_type = Class.new(FieldStruct::Types::Date) do
        def self.default_format
          '%m/%d/%Y'
        end
      end
      stub_const('USDateType', us_date_type)

      acme = Module.new
      stub_const('AcmeUSDate', acme)
      acme.define_singleton_method(:field_types) do
        @field_types ||= FieldStruct.new_registry { register :us_date, USDateType }
      end

      klass = Class.new(described_class)
      stub_const('AcmeUSDate::Event', klass)
      klass.class_eval { required :on, :us_date }

      expect(klass.new(on: '01/15/2024').on).to eq(Date.new(2024, 1, 15))
      expect(klass.new(on: '01/15/2024').as_json[:on]).to eq('01/15/2024')
    end
  end
end
