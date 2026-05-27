# Types & Coercion

Each declared field is backed by a **Type class** that does two jobs:

1. Decide whether an input value is acceptable.
2. Coerce it into the type's domain (string into Integer, ISO-8601 string into Date, etc.).

This page covers the built-in types and how coercion works. For per-type configuration knobs (`format:`, `round:`, etc.), see [Field Options](./field-options). For adding your own types, see [Custom Types & Registries](./custom-types).

## Built-in types

| Symbol | Class | Notes |
|--------|-------|-------|
| `:string` | `Types::String` | Coerces via `#to_s`; treats empty / whitespace-only as missing. |
| `:immutable_string` | `Types::ImmutableString` | Like `:string` but returns frozen strings. |
| `:symbol` | `Types::Symbol` | Accepts Symbol or String. |
| `:integer` | `Types::Integer` | Coerces via `Integer(value)`; rejects malformed numerics. |
| `:float` | `Types::Float` | Coerces via `Float(value)`; supports `round:`. |
| `:big_decimal` / `:decimal` | `Types::BigDecimal` | Coerces via `BigDecimal(value, …)`; supports `round:`. |
| `:boolean` | `Types::Boolean` | Configurable `truthy:` / `falsy:` sets. |
| `:date` | `Types::Date` | Supports `format:` (strftime or `:iso8601`). |
| `:time` | `Types::Time` | Same `format:` story. |
| `:datetime` | `Types::DateTime` | Same `format:` story. |
| `:value` | `Types::Value` | Catch-all: anything goes through unchanged. |
| `:array` | `Types::Array` | Element type via `of:`. |
| `:union` | `Types::Union` | Multi-type via `of:`. |
| `:uuid` | `Types::UUID` | Validates UUID shape. |
| `:url` | `Types::URL` | Validates URL shape (configurable). |
| `:email` | `Types::Email` | Validates email shape (configurable). |
| `:binary` | `Types::Binary` | Raw binary string (ASCII-8BIT). |

The names live in a global registry at `FieldStruct.types`:

```ruby
FieldStruct.types
# => #<FS::Registry types=[:string, :integer, :float, …, :binary]>
```

## How a value moves through coercion

Every setter — including the one the constructor calls — runs the same pipeline:

```
incoming value
   │
   ▼
type_instance.coerce(value, **field.options)
   │
   ├─ success → store coerced value
   │
   └─ failure (ArgumentError, TypeError, FieldStruct::Error)
        │
        └─ apply coercion_policy
             ├─ :keep_raw  → store the raw value, record an error    (default)
             ├─ :replace   → store nil, record an error
             └─ :raise     → raise FieldStruct::CoercionError
```

Coercion is run on **every** assignment, not just at construction. Reassigning a field re-runs the pipeline and rewrites that field's error entry.

## Coercion policy

The class macro `coercion_policy` chooses how the pipeline reacts to failures:

```ruby
class StrictUser < FieldStruct::Base
  coercion_policy :raise           # opt out of soft errors

  required :age, :integer
end

StrictUser.new(age: 'banana')
# => FieldStruct::CoercionError: cannot coerce "banana" to Integer
```

Three options:

| Policy | Storage on failure | Errors? | Raises? |
|--------|---------------------|---------|---------|
| `:keep_raw` (default) | the raw input | yes | no |
| `:replace` | `nil` | yes | no |
| `:raise` | n/a | n/a | yes (`CoercionError`) |

The macro is inherited along the class chain — subclasses pick up the parent's policy unless they declare their own.

## Per-field override

A single field can override the class policy:

```ruby
class User < FieldStruct::Base
  coercion_policy :keep_raw                   # the rest of the class
  required :age, :integer, coercion_policy: :raise   # but age is strict
end
```

## Missing values

A separate concept from "failed coercion." Each type knows what counts as **missing** for the purpose of presence checks:

- `nil` is missing for every type.
- For `:string` (and family), empty/whitespace strings are missing.
- For `:array`, an empty array is missing.

Presence checking happens during validation — see [Validation](./validation).

## Two examples

### Coercion succeeds, value is stored coerced

```ruby
class Order < FieldStruct::Base
  required :total, :big_decimal, round: 2
end

o = Order.new(total: '19.999')
o.total            # => #<BigDecimal:0x… '0.2000e2'>   (rounded to 2 dp)
o.valid?           # => true
```

### Coercion fails, the default policy logs an error

```ruby
class Reading < FieldStruct::Base
  required :temp, :float
end

r = Reading.new(temp: 'warm')
r.temp             # => "warm"   (raw value kept under :keep_raw)
r.valid?           # => false
r.errors[:temp]    # => ["could not coerce to Float"]
```

Reassigning a valid value clears that field's error:

```ruby
r.temp = '72.3'
r.temp             # => 72.3
r.errors[:temp]    # => []
```

## Next

- [Custom Types & Registries](./custom-types) — extend or replace the type set in your namespace
- [Field Options](./field-options) — every type-specific knob (`format:`, `round:`, `truthy:`, `of:`, etc.)
