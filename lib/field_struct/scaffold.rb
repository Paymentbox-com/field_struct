# frozen_string_literal: true

module FieldStruct
  # Scaffolds FieldStruct class source from one or more JSON example objects.
  #
  # The goal is a *working prototype* you then refine by hand — the generator
  # is deliberately conservative about types and never guesses past the
  # evidence. Pass a single object to seed the shape, or an array of
  # same-shape objects to gather more signal (empty fields get resolved from
  # other samples, presence drives required/optional, and small repeated
  # vocabularies surface as enum candidates). A single object is just the
  # one-sample case of the same engine.
  #
  #   FieldStruct::Scaffold.from_json(<<~JSON, class_name: 'User')
  #     {"name": "Al", "age": 30, "active": true}
  #   JSON
  #   # class User < FieldStruct::Base
  #   #   required :name, :string
  #   #   required :age, :integer
  #   #   required :active, :boolean
  #   # end
  #
  # Inference rules (conservative on purpose):
  #
  # * JSON object → a nested FieldStruct class (emitted before its parent).
  # * JSON array → +:array, of: <element type>+ (element class for arrays of objects).
  # * JSON +true+/+false+ → +:boolean+; integer → +:integer+; real → +:float+.
  # * JSON string → +:string+ — *including numeric-looking strings* (an
  #   +authorization_code+ must not become an Integer). Hints like "maybe
  #   :big_decimal" are emitted as trailing comments, not committed types.
  # * required when present and non-blank across *every* sample; else optional.
  #
  # The developer adds enums, descriptions, formats, and final scalar types;
  # the comments point at where.
  module Scaffold
    # Matches an integer- or decimal-looking string (kept as +:string+, only hinted).
    NUMERIC_STRING = /\A-?\d+(?:\.\d+)?\z/
    # Most distinct repeated string values before a field is flagged as an enum candidate.
    ENUM_MAX_DISTINCT = 6
    # Ruby keywords that can't be used as attribute names (suffixed with +_field+).
    RESERVED = %w[
      BEGIN END alias and begin break case class def defined? do else elsif end
      ensure false for if in module next nil not or redo rescue retry return self
      super then true undef unless until when while yield __FILE__ __LINE__
    ].freeze

    # Generate FieldStruct class source from JSON example(s).
    #
    # @param input [String, Hash, Array<Hash>] a JSON string (object or array
    #   root), a parsed Hash, or an Array of same-shape Hashes
    # @param class_name [String] the root class name
    # @return [String] Ruby source defining the class and any nested classes
    # @raise [ArgumentError] for an empty set or non-object samples
    def self.from_json(input, class_name: 'Generated')
      samples = normalize(input)
      raise ArgumentError, 'no samples to scaffold from' if samples.empty?
      raise ArgumentError, 'every sample must be a JSON object' unless samples.all?(::Hash)

      classes = []
      emit_object(class_name, samples, classes, [])
      "#{classes.join("\n\n")}\n"
    end

    # @return [Array<Hash>] the sample set (a lone object becomes a set of one)
    def self.normalize(input)
      data = input.is_a?(::String) ? Oj.load(input, mode: :strict) : input
      case data
      when ::Array then data
      when ::Hash then [data]
      else
        raise ArgumentError, "expected a JSON object or array of objects, got #{data.class}"
      end
    end
    private_class_method :normalize

    # Build the class for +samples+ as +class_name+, appending nested classes
    # to +classes+ first (post-order, so references resolve), and return the
    # (deduplicated) class name used.
    def self.emit_object(class_name, samples, classes, used)
      name = unique_name(class_name, used)
      total = samples.length
      mappings = {}
      lines = ordered_keys(samples).map do |key|
        attr = safe_attr(key)
        mappings[attr] = key unless attr == key
        field_line(attr, observe(samples, key), total, classes, used)
      end
      classes << build_class(name, mappings, lines)
      name
    end
    private_class_method :emit_object

    # @return [Hash] +{ present: Integer, values: Array }+ for +key+ across samples
    def self.observe(samples, key)
      present = samples.select { |sample| sample.key?(key) }
      {present: present.length, values: present.map { |sample| sample[key] }}
    end
    private_class_method :observe

    def self.field_line(attr, obs, total, classes, used)
      values = obs[:values]
      non_nil = values.compact
      missing = values.count(&:nil?) + values.count { |v| blank_string?(v) }
      required = obs[:present] == total && missing.zero?
      avail = availability_comment(obs[:present], total, missing)

      type_part, hint = type_for(attr, non_nil, classes, used)
      decorate("#{required ? "required" : "optional"} :#{attr}, #{type_part}", avail, hint)
    end
    private_class_method :field_line

    # @return [Array(String, String)] +[type_part, comment_hint]+
    def self.type_for(attr, non_nil, classes, used)
      if non_nil.any?(::Hash)
        [emit_object(class_name_for(attr), non_nil.grep(::Hash), classes, used), nil]
      elsif non_nil.any?(::Array)
        of_part, hint = array_element(attr, non_nil.grep(::Array).flatten(1), classes, used)
        [":array, of: #{of_part}", hint]
      else
        sym, hint = infer_scalar(non_nil)
        [":#{sym}", hint]
      end
    end
    private_class_method :type_for

    # @return [Array(String, String)] +of:+ value and a comment hint
    def self.array_element(attr, elements, classes, used)
      non_nil = elements.compact
      return [':value', 'empty array(s) in samples — element type unknown'] if non_nil.empty?
      return [emit_object(class_name_for(singularize(attr)), non_nil.grep(::Hash), classes, used), nil] \
        if non_nil.any?(::Hash)

      sym, hint = infer_scalar(non_nil)
      [":#{sym}", hint]
    end
    private_class_method :array_element

    # @return [Array(Symbol, String)] inferred scalar type and a comment hint
    def self.infer_scalar(values)
      return [:string, 'always null/absent in samples — type unknown'] if values.empty?

      kinds = values.map { |v| scalar_kind(v) }.uniq
      return [:boolean, nil] if kinds == [:boolean]
      return [:integer, nil] if kinds == [:integer]
      return [:float, nil] if (kinds - %i[integer float]).empty?
      return string_inference(values) if kinds == [:string]

      [:value, "mixed types in samples (#{kinds.join(", ")}) — review"]
    end
    private_class_method :infer_scalar

    def self.string_inference(values)
      non_empty = values.reject { |s| blank_string?(s) }
      return [:string, 'always empty in samples — type unknown'] if non_empty.empty?

      if non_empty.all? { |s| s.match?(NUMERIC_STRING) }
        suggestion = non_empty.any? { |s| s.include?('.') } ? ':big_decimal' : ':integer'
        return [:string, %(numeric-looking (e.g. "#{non_empty.first}") — #{suggestion}? or keep :string if an id/code)]
      end

      distinct = non_empty.uniq
      if non_empty.length >= 3 && distinct.length < non_empty.length && distinct.length <= ENUM_MAX_DISTINCT
        return [:string, "values: #{distinct.inspect} — enum?"]
      end

      [:string, nil]
    end
    private_class_method :string_inference

    def self.scalar_kind(value)
      case value
      when true, false then :boolean
      when ::Integer then :integer
      when ::Float then :float
      when ::String then :string
      else :other
      end
    end
    private_class_method :scalar_kind

    def self.build_class(name, mappings, lines)
      body = []
      unless mappings.empty?
        body << "  serialize :json, #{mappings.map { |attr, key| "#{attr}: #{key.inspect}" }.join(", ")}"
        body << ''
      end
      body.concat(lines)
      body << '  # (no fields detected in samples)' if body.empty?
      "class #{name} < FieldStruct::Base\n#{body.join("\n")}\nend"
    end
    private_class_method :build_class

    def self.decorate(declaration, *comment_parts)
      parts = comment_parts.compact.reject(&:empty?)
      line = "  #{declaration}"
      parts.empty? ? line : "#{line} # #{parts.join("; ")}"
    end
    private_class_method :decorate

    def self.availability_comment(present, total, missing)
      return "present #{present}/#{total}" if present < total
      # Only note partial emptiness; when every sample is empty the scalar
      # hint ("always empty — type unknown") already says so.
      return "empty/null in #{missing}/#{total}" if missing.positive? && missing < total

      nil
    end
    private_class_method :availability_comment

    # First-seen union of keys across all samples.
    def self.ordered_keys(samples)
      samples.each_with_object([]) do |sample, keys|
        sample.each_key { |key| keys << key unless keys.include?(key) }
      end
    end
    private_class_method :ordered_keys

    def self.unique_name(base, used)
      name = base
      suffix = 1
      while used.include?(name)
        suffix += 1
        name = "#{base}#{suffix}"
      end
      used << name
      name
    end
    private_class_method :unique_name

    def self.class_name_for(key)
      name = camelize(key)
      name = "N#{name}" unless name.match?(/\A[A-Z]/)
      name
    end
    private_class_method :class_name_for

    def self.camelize(str)
      str.to_s.split(/[^a-zA-Z0-9]+/).reject(&:empty?).map { |part| part[0].upcase + (part[1..] || '') }.join
    end
    private_class_method :camelize

    # Naive: strip one trailing "s". Good enough for a prototype name; the
    # developer renames as needed.
    def self.singularize(str)
      str.end_with?('s') && str.length > 1 ? str[0..-2] : str
    end
    private_class_method :singularize

    def self.safe_attr(key)
      attr = key.to_s.gsub(/([a-z\d])([A-Z])/, '\1_\2').gsub(/[^a-zA-Z0-9]+/, '_').downcase
      attr = attr.sub(/\A_+/, '').sub(/_+\z/, '')
      attr = "field_#{attr}" if attr.empty? || attr.match?(/\A\d/)
      attr = "#{attr}_field" if RESERVED.include?(attr)
      attr
    end
    private_class_method :safe_attr

    def self.blank_string?(value)
      value.is_a?(::String) && value.strip.empty?
    end
    private_class_method :blank_string?
  end
end
