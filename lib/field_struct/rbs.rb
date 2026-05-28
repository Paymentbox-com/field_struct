# frozen_string_literal: true

module FieldStruct
  # Generates RBS type signatures for the *generated* instance surface of
  # user-defined {FieldStruct::Base} subclasses — the per-field accessors the
  # +field+ DSL defines dynamically.
  #
  # Sord generates +sig/field_struct.rbs+ from the library's static source, so
  # it covers {Base}, {Types}, {Registry}, … but it can never see +User#name+
  # or +User#age=+: those methods don't exist until a consumer declares the
  # fields. This is the deferred "track 2" of the plan's RBS strategy (D13) —
  # walk a subclass's {Metadata} and emit signatures for its accessors so
  # downstream Steep / Solargraph can type-check code that touches them.
  #
  #   class User < FieldStruct::Base
  #     required :name, :string
  #     optional :age,  :integer
  #   end
  #
  #   puts FieldStruct::RBS.generate(User)
  #   # class User < ::FieldStruct::Base
  #   #   attr_reader name: ::String
  #   #   def name=: (untyped value) -> untyped
  #   #
  #   #   attr_reader age: ::Integer?
  #   #   def age=: (untyped value) -> untyped
  #   # end
  #
  # Design choices:
  #
  # * **Reader type** is the field's {Types::Base#ruby_type}. Nullability
  #   follows {Field#required?}: required → +T+, optional → +T?+. A
  #   constructed-but-invalid instance (or a +:replace+ coercion failure) can
  #   still hold +nil+ in a required field — the signature reflects declared
  #   intent, not runtime validity.
  # * **Writer** is +(untyped) -> untyped+. The type coerces loose input
  #   (+user.age = "30"+ is valid), so a strict writer would be a false
  #   positive.
  # * **+new+ / +initialize+** are inherited from {Base} (+(?Hash) -> void+),
  #   which already accepts +User.new(name: ...)+.
  #
  # Each call emits one class. Referenced types (nested structs, array
  # elements) appear as qualified names (+::Address+) — generate RBS for those
  # classes too so the references resolve.
  module RBS
    BOOL_CLASSES = [TrueClass, FalseClass].freeze
    private_constant :BOOL_CLASSES

    # Generate RBS source for a single FieldStruct subclass.
    #
    # @param klass [Class<FieldStruct::Base>]
    # @return [String] RBS declaring the class (wrapped in its module nesting)
    #   and a typed reader + permissive writer for every field it declares
    # @raise [ArgumentError] when +klass+ is not a named {FieldStruct::Base}
    #   subclass
    def self.generate(klass)
      unless klass.is_a?(::Class) && klass < FieldStruct::Base
        raise ArgumentError,
          "FieldStruct::RBS.generate expects a FieldStruct::Base subclass, got #{klass.inspect}"
      end
      raise ArgumentError, 'cannot generate RBS for an anonymous class' unless klass.name

      wrap_namespace(klass.name, class_block(klass))
    end

    # Build the +class ... end+ block (unindented, no surrounding modules).
    #
    # @param klass [Class<FieldStruct::Base>]
    # @return [String]
    def self.class_block(klass)
      simple = klass.name.split('::').last
      lines = ["class #{simple} < ::#{klass.superclass.name}"]
      own_fields(klass).each_with_index do |field, index|
        lines << '' unless index.zero?
        lines << "  attr_reader #{field.name}: #{reader_type(field)}"
        lines << "  def #{field.name}=: (untyped value) -> untyped"
      end
      lines << 'end'
      lines.join("\n")
    end
    private_class_method :class_block

    # Fields declared on +klass+ itself — inherited fields (the same {Field}
    # objects merged in at inheritance time) belong to the parent's RBS.
    #
    # @param klass [Class<FieldStruct::Base>]
    # @return [Array<Field>]
    def self.own_fields(klass)
      parent = klass.superclass
      parent_meta = parent.respond_to?(:metadata) ? parent.metadata : nil
      klass.metadata.reject { |field| parent_meta && parent_meta[field.name].equal?(field) }
    end
    private_class_method :own_fields

    # @param field [Field]
    # @return [String] the reader's RBS type, made nullable when optional
    def self.reader_type(field)
      base = type_for(field.type_instance, field.options)
      field.required? ? base : "#{base}?"
    end
    private_class_method :reader_type

    # Map a type instance (plus its field options, needed for arrays) to an
    # RBS type expression.
    #
    # @param type_instance [Types::Base]
    # @param options [Hash{Symbol=>Object}]
    # @return [String]
    def self.type_for(type_instance, options)
      return "::Array[#{element_type(options[:of_type])}]" if type_instance.is_a?(FieldStruct::Types::Array)

      ruby_type = type_instance.ruby_type
      classes = ruby_type.is_a?(::Array) ? ruby_type : [ruby_type]
      return 'bool' if classes.sort_by(&:name) == BOOL_CLASSES.sort_by(&:name)

      mapped = classes.map { |klass| class_to_rbs(klass) }.uniq
      mapped.one? ? mapped.first : "(#{mapped.join(" | ")})"
    end
    private_class_method :type_for

    # The element type of an array field, derived from its +:of_type+ (a
    # +Types::Base+ subclass for stock types, or a built instance for
    # parameterized ones like {Types::Nested}).
    #
    # @param of_type [Class, Types::Base, nil]
    # @return [String]
    def self.element_type(of_type)
      return 'untyped' if of_type.nil?

      instance = of_type.is_a?(::Class) ? of_type.new : of_type
      type_for(instance, {})
    end
    private_class_method :element_type

    # @param klass [Class] a Ruby class from a {Types::Base#ruby_type}
    # @return [String] qualified RBS name, or +untyped+ for the value type's +::Object+
    def self.class_to_rbs(klass)
      return 'untyped' if klass == ::Object

      "::#{klass.name}"
    end
    private_class_method :class_to_rbs

    # Wrap an inner block in the +module ... end+ nesting implied by a
    # qualified class name, indenting two spaces per level.
    #
    # @param full_name [String] e.g. +"Acme::Order"+
    # @param inner [String] the class block
    # @return [String] RBS source ending in a trailing newline
    def self.wrap_namespace(full_name, inner)
      modules = full_name.split('::')[0...-1]
      block = inner
      modules.reverse_each { |mod| block = "module #{mod}\n#{indent(block)}\nend" }
      "#{block}\n"
    end
    private_class_method :wrap_namespace

    # @param text [String]
    # @return [String] +text+ with every non-blank line indented two spaces
    def self.indent(text)
      text.split("\n", -1).map { |line| line.empty? ? line : "  #{line}" }.join("\n")
    end
    private_class_method :indent
  end
end
