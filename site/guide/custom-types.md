# Custom Types & Registries

The built-in types cover the common ground, but every domain has its own value classes — `Money`, `Currency`, `PhoneNumber`, an internal `UserId` wrapper. FieldStruct's **Registry** is how you add them without forking the gem.

## The Registry

`FieldStruct.types` is the global registry that maps symbols (`:string`, `:integer`, …) to type classes:

```ruby
FieldStruct.types
# => #<FS::Registry types=[:string, :integer, :float, …, :binary]>

FieldStruct.types.lookup(:integer)
# => FieldStruct::Types::Integer

FieldStruct.types.key?(:money)
# => false
```

A registry can have a **parent**. Lookup walks the chain: the local registry first, then up. That's what lets a namespace add types without mutating the global one.

## Writing a custom type

Subclass `FieldStruct::Types::Base` and implement `#coerce` and `#ruby_type`:

```ruby
module Acme
  module Types
    class Money < FieldStruct::Types::Base
      # Coerce the input into a Money instance. Raise on inputs you
      # genuinely can't handle — the parent's coercion_policy decides
      # what to do with the failure.
      def coerce(value, **)
        return nil               if value.nil?
        return value             if value.is_a?(::Money)
        return ::Money.from_cents(value) if value.is_a?(Integer)
        return ::Money.parse(value)      if value.is_a?(String)

        raise ::ArgumentError, "cannot coerce #{value.class} to Money"
      end

      def ruby_type
        ::Money
      end

      # Optional: override #missing? if your "empty" notion is broader
      # than nil. Default is nil-only.
    end
  end
end
```

## Per-namespace registries

Don't push your gem-specific types into `FieldStruct.types`. Build a registry parented to it instead:

```ruby
module Acme
  def self.field_types
    @field_types ||= FieldStruct.new_registry do
      register :money,         Acme::Types::Money
      register :phone_number,  Acme::Types::PhoneNumber

      # An alias to another already-registered name:
      register :amount, :money
    end
  end

  class Base < FieldStruct::Base
    def self.field_registry
      Acme.field_types
    end
  end
end
```

Now subclasses of `Acme::Base` look up types in `Acme.field_types` first, falling back to `FieldStruct.types`:

```ruby
class Acme::Invoice < Acme::Base
  required :id,     :string
  required :amount, :money    # found in Acme.field_types
  required :issued, :date     # falls back to FieldStruct.types
end
```

`FieldStruct.new_registry` is sugar for `Registry.new(parent).tap { |r| ... }`. Pass `parent: nil` if you want an unparented registry — no fallback chain.

## Aliases

Registering one name as another resolves the target *eagerly*:

```ruby
FieldStruct.new_registry do
  register :decimal, :big_decimal   # decimal is now an alias for big_decimal
end
```

The target must already exist in this registry or in a parent. A later `register` of the same name silently overwrites the prior entry — that's the mechanism that lets a namespace registry **shadow** a parent's type.

## Per-type field options

If your type accepts options (like `:string` accepts `format:`, or `:date` accepts `format:`), declare them as kwargs in your `#coerce`:

```ruby
class CurrencyAmount < FieldStruct::Types::Base
  def coerce(value, currency: 'USD', **)
    return nil if value.nil?
    Money.new(value, currency)
  end

  def ruby_type
    Money
  end
end
```

Then at the call site:

```ruby
class Invoice < FieldStruct::Base
  required :amount, :currency_amount, currency: 'EUR'
end
```

For more advanced symbol-preset resolution (like `:date` turning `format: :iso8601` into a strftime string), see how the built-in `Date`, `Time`, and `DateTime` types use `Types::PresetResolver` and `default_format` class methods.

## Inspecting your registry

The `Registry#inspect` is concise:

```ruby
Acme.field_types
# => #<FS::Registry types=[:money, :phone_number, :amount] parent>

Acme.field_types.parent
# => #<FS::Registry types=[:string, :integer, :float, …]>
```

The `parent` marker tells you a fallback chain exists; it doesn't recursively dump the parent's types.

## Next

- [Field Options](./field-options) — every option the built-in types accept
- [Validation](./validation) — beyond coercion: cross-field rules, the `validate` macro
