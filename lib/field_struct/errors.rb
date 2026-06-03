# frozen_string_literal: true

module FieldStruct
  # Per-instance collection of validation messages, keyed by field name.
  #
  # Shaped after ActiveModel::Errors but reuses none of its code. Each
  # FieldStruct instance gets its own Errors object; the setter pipeline
  # clears and rewrites a field's entry on every assignment.
  class Errors
    def initialize
      @messages = {}
    end

    # @param field_name [Symbol, String]
    # @return [Array<String>] messages for the field, or an empty array
    def [](field_name)
      @messages[field_name.to_sym] || []
    end

    # @param field_name [Symbol, String]
    # @param message [String]
    # @return [Array<String>] the field's updated message list
    def add(field_name, message)
      key = field_name.to_sym
      (@messages[key] ||= []) << message
    end

    # Drop every message for a field.
    #
    # @param field_name [Symbol, String]
    # @return [void]
    def clear(field_name)
      @messages.delete(field_name.to_sym)
      nil
    end

    # @return [Boolean] true when no field has any messages
    def empty?
      @messages.each_value.all?(&:empty?)
    end

    # @return [Hash{Symbol=>Array<String>}] snapshot of field → messages,
    #   skipping fields with empty message lists
    def to_h
      @messages.reject { |_, msgs| msgs.empty? }
    end
    alias messages to_h

    # Every message rendered as a full, human-readable sentence: the
    # humanized field name prepended to each message. Messages on +:base+
    # (the cross-field convention) pass through unprefixed — they are
    # already complete sentences. Order follows field insertion order, then
    # message order within a field.
    #
    #   errors.add(:first_name, 'is required')
    #   errors.full_messages   # => ["First name is required"]
    #
    # @return [Array<String>]
    def full_messages
      to_h.flat_map do |field, msgs|
        next msgs if field == :base

        prefix = humanize(field)
        msgs.map { |msg| "#{prefix} #{msg}" }
      end
    end

    # @return [String]
    def inspect
      prefix = "#{FieldStruct.inspect_namespace}::Errors"
      return "#<#{prefix} empty>" if empty?

      pairs = to_h.map { |field, msgs| "#{field}=#{msgs.inspect}" }.join(' ')
      "#<#{prefix} #{pairs}>"
    end

    private

    # Turn a field name into a display label for {#full_messages}:
    # underscores become spaces and the first character is upcased.
    # Deliberately minimal — no inflection, no +_id+ stripping, no i18n.
    #
    # @param field [Symbol]
    # @return [String]
    def humanize(field)
      field.to_s.tr('_', ' ').sub(/\A./, &:upcase)
    end
  end
end
