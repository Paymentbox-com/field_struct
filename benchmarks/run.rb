# frozen_string_literal: true

# Indicative FieldStruct timings. Dependency-free on purpose: `benchmark` is
# no longer a default gem on Ruby 4, and this must run from a plain checkout.
#
#   bundle exec rake bench
#   ruby benchmarks/run.rb [seconds-per-case]   # default 1.0
#
# Each case is warmed up, then run in batches until the time budget is spent;
# the report is the mean time per call. Numbers move with CPU, Ruby version
# and load — compare runs on the same machine, not across machines.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'field_struct'
require 'etc'

module Bench
  # Five fields, one of each common scalar.
  class Payment < FieldStruct::Base
    required :id, :string
    required :cents, :integer
    required :currency, :string
    optional :paid, :boolean
    optional :note, :string
  end

  # The same shape with strict: true where it applies.
  class StrictPayment < FieldStruct::Base
    required :id, :string, strict: true
    required :cents, :integer, strict: true
    required :currency, :string, strict: true
    optional :paid, :boolean
    optional :note, :string, strict: true
  end

  class Address < FieldStruct::Base
    required :street, :string
    required :city, :string
    optional :zip, :string
  end

  class Customer < FieldStruct::Base
    required :name, :string
    required :address, Address
  end

  class Batch < FieldStruct::Base
    required :ids, :array, of: :integer
  end

  # Every validation path on assign, plus a cross-field validator.
  class Checked < FieldStruct::Base
    required :email, :email
    required :currency, :string, enum: %w[USD EUR GBP]
    required :cents, :integer, in: 1..1_000_000
    required :code, :string, format: /\A[A-Z]{3}-\d{4}\z/
    required :starts, :date
    required :ends, :date

    validate { |r| r.errors.add(:base, 'ends before it starts') if r.starts && r.ends && r.ends < r.starts }
  end

  PAYMENT = {id: 'pay_1', cents: 1999, currency: 'USD', paid: true, note: 'thanks'}.freeze
  PAYMENT_JSON = Payment.new(PAYMENT).to_json
  PAYMENT_RECORD = Payment.new(PAYMENT)
  CUSTOMER = {name: 'Ada', address: {street: '1 Main', city: 'Provo', zip: '84601'}}.freeze
  IDS = (1..100).to_a.freeze
  CHECKED = {email: 'a@example.com', currency: 'EUR', cents: 500, code: 'ABC-1234',
             starts: '2026-01-01', ends: '2026-02-01'}.freeze

  CASES = {
    'new (5 fields)' => -> { Payment.new(PAYMENT) },
    'new (5 fields, strict: true)' => -> { StrictPayment.new(PAYMENT) },
    'from_json (5 fields)' => -> { Payment.from_json(PAYMENT_JSON) },
    'to_json (5 fields)' => -> { PAYMENT_RECORD.to_json },
    'new (nested struct)' => -> { Customer.new(CUSTOMER) },
    'new (array of 100 integers)' => -> { Batch.new(ids: IDS) },
    'new (validation-heavy, 6 fields)' => -> { Checked.new(CHECKED) }
  }.freeze

  module_function

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # @return [Float] mean seconds per call
  def measure(callable, budget)
    200.times { callable.call } # warm up
    calls = 0
    batch = 100
    started = now
    elapsed = 0.0
    while elapsed < budget
      batch.times { callable.call }
      calls += batch
      elapsed = now - started
    end
    elapsed / calls
  end

  def cpu
    if RUBY_PLATFORM.include?('darwin')
      `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip
    elsif File.readable?('/proc/cpuinfo')
      File.read('/proc/cpuinfo')[/^model name\s*:\s*(.+)$/, 1].to_s
    end.then { |name| name.nil? || name.empty? ? RUBY_PLATFORM : name }
  end

  def run(budget)
    puts "FieldStruct #{FieldStruct::VERSION} · #{RUBY_DESCRIPTION}"
    puts "CPU: #{cpu} (#{Etc.nprocessors} cores) · #{budget}s per case"
    puts
    puts format(ROW, 'case', 'µs/call', 'calls/sec')
    puts "|#{"-" * 36}|#{"-" * 11}:|#{"-" * 13}:|"
    CASES.each do |label, callable|
      seconds = measure(callable, budget)
      puts format(ROW, label, format('%.2f', seconds * 1_000_000), delimit((1 / seconds).round))
    end
  end

  ROW = '| %-34s | %10s | %12s |'

  # @return [String] 1234567 as "1,234,567"
  def delimit(number)
    number.to_s.reverse.scan(/\d{1,3}/).join(',').reverse
  end
end

Bench.run(Float(ARGV.fetch(0, '1.0')))
