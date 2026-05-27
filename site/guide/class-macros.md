# Class Macros

The behavior of a FieldStruct class is configured through class-level macros, not constructor arguments. Each macro is **inherited** along the class chain — declare it on a base, every subclass picks it up unless it overrides.

## `coercion_policy`

How the setter pipeline reacts when `Type#coerce` raises:

```ruby
class StrictUser < FieldStruct::Base
  coercion_policy :raise        # raise FieldStruct::CoercionError

  required :age, :integer
end

StrictUser.new(age: 'banana')
# => FieldStruct::CoercionError: cannot coerce "banana" to Integer
```

Three options:

| Policy | On coercion failure | `errors` | Raises |
|--------|---------------------|----------|--------|
| `:keep_raw` *(default)* | stores the raw input | yes | no |
| `:replace` | stores `nil` | yes | no |
| `:raise` | — | n/a | yes |

The default is `:keep_raw` so an instance with bad input is **still alive** — you can read back the raw input, see the error, and let the user (or upstream service) correct it.

A single field can override:

```ruby
class User < FieldStruct::Base
  coercion_policy :keep_raw
  required :age, :integer, coercion_policy: :raise   # but age is strict
end
```

## `unknown_attributes`

How `initialize` reacts when the input hash contains keys you didn't declare:

```ruby
class User < FieldStruct::Base
  unknown_attributes :raise        # default: :ignore

  required :name, :string
end

User.new(name: 'Alice', age: 30)
# => FieldStruct::UnknownAttributeError: unknown attribute :age
```

Two options:

| Mode | What happens |
|------|--------------|
| `:ignore` *(default)* | Extra keys silently dropped on the floor. |
| `:raise` | Constructor raises `UnknownAttributeError`. |

`:raise` is the right call when you're constructing from an external payload and want to *know* if the schema drifted. `:ignore` is the right call when you're getting partial data from many sources and only care about your subset.

## `immutable!`

Mark the class read-only after construction:

```ruby
class Address < FieldStruct::Base
  immutable!

  required :street, :string
  required :city,   :string
end

a = Address.new(street: '742 Evergreen', city: 'Springfield')
a.street = '1 Main'
# => FieldStruct::ImmutableError: Address#street is immutable
```

The constructor still sets the fields normally — it's only post-construction reassignment that's blocked. `immutable!` is a **one-way** switch: no companion `mutable!` macro. Subclasses inherit the immutability.

## `frozen!`

Stronger than `immutable!`: freeze the Ruby object itself once construction settles. Every ivar (errors, attribute hash, …) becomes read-only:

```ruby
class Config < FieldStruct::Base
  frozen!

  required :host, :string
  required :port, :integer
end

c = Config.new(host: 'localhost', port: 5432)
c.frozen?    # => true
c.host = 'other'
# => FrozenError: can't modify frozen Config
```

`frozen!` implies `immutable!` semantically — and goes further: even `errors.clear(:host)` raises, because the errors object is frozen too. Use it when you've reached a state you genuinely never want to mutate (post-init configuration; cached value objects).

## How inheritance works

Each macro records its state on the class. The subclass `inherited` hook copies the configured state forward; if the subclass declares its own, that wins:

```ruby
class App < FieldStruct::Base
  coercion_policy :raise
  unknown_attributes :raise
end

class StrictUser < App
  required :name, :string
  # inherits both :raise settings
end

class LooseUser < App
  coercion_policy :keep_raw   # local override
  required :name, :string
end
```

This is the same shape used by the field-level metadata: subclass-level wins, parent-level fills in.

## When *not* to use them

- **`immutable!` / `frozen!`** make a class harder to use in dev/test contexts where you want to poke at instances. Reserve them for classes that have *settled* — configuration values, audit records, anything that's "this is what we agreed on, don't move it."
- **`unknown_attributes :raise`** is great for code that owns its schema. For boundary code that accepts arbitrary input and filters down — keep it `:ignore`.
- **`coercion_policy :raise`** is right when bad data is *exceptional*. If bad data is *expected* (form input, partial uploads), `:keep_raw` so you can report the errors back to the user.

## Next

- [Serialization](./serialization) — JSON I/O across the class macros
- [Field Options](./field-options) — per-field configuration that pairs with these class-level switches
