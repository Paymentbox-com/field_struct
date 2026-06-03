# frozen_string_literal: true

module FieldStruct
  # Name → type-class map with optional parent fallback.
  #
  # Holds the resolution table that maps symbolic type names (`:string`,
  # `:integer`, …) to the {Types} classes that implement them. A namespace
  # can build its own registry parented to the base ({FieldStruct.types})
  # to extend or override the default set without mutating it.
  class Registry
    # @return [Registry, nil] the parent registry, or +nil+ for an unparented one
    attr_reader :parent

    # @param parent [Registry, nil] the registry to fall back to when a name
    #   isn't found locally
    def initialize(parent = nil)
      @parent = parent
      @types = {}
    end

    # Register a type class — or an alias to an already-registered name.
    #
    #   registry.register(:integer, MyInteger)        # type class
    #   registry.register(:decimal, :big_decimal)     # alias (resolved now)
    #
    # Aliases are eagerly resolved through {#lookup}, so the alias target
    # must already be registered (locally or in a parent). A later
    # registration of the same name overwrites silently — this is the
    # mechanism that lets a namespace registry shadow a parent's type.
    #
    # @param name [Symbol, String] the name to register
    # @param target [Class, Symbol] a type class, or an existing registered name
    # @return [self]
    # @raise [KeyError] when +target+ is a Symbol that isn't registered yet
    def register(name, target)
      type_class = target.is_a?(::Symbol) ? lookup(target) : target
      @types[name.to_sym] = type_class
      self
    end

    # Resolve a name to its type class, walking the parent chain.
    #
    # @param name [Symbol, String]
    # @return [Class] the type class
    # @raise [KeyError] when the name isn't registered locally or via the parent chain
    def lookup(name)
      key = name.to_sym
      return @types[key] if @types.key?(key)
      return @parent.lookup(key) if @parent

      raise ::KeyError, "no FieldStruct type registered for #{name.inspect}"
    end

    # Whether the name resolves to anything (locally or via the parent chain).
    #
    # @param name [Symbol, String]
    # @return [Boolean]
    def key?(name)
      key = name.to_sym
      return true if @types.key?(key)

      !@parent.nil? && @parent.key?(key)
    end

    # Every distinct type class resolvable through this registry, including
    # those inherited from the parent chain. Local entries come first;
    # duplicates (e.g. an alias pointing at an already-listed class, or a
    # parent class also registered locally) are removed.
    #
    # @return [Array<Class>] deduplicated, local-first
    def type_classes
      own = @types.values
      (@parent ? own + @parent.type_classes : own).uniq
    end

    # @return [String] one-line summary of the locally-registered names
    #   (does not enumerate the parent chain), with a +parent+ marker
    #   when the registry has one
    def inspect
      parts = ["types=#{@types.keys.inspect}"]
      parts << 'parent' if @parent
      "#<#{FieldStruct.inspect_namespace}::Registry #{parts.join(" ")}>"
    end
  end
end
