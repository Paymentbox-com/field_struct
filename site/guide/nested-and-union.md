# Nested & Union Types

FieldStruct composes. A field can hold another FieldStruct (or several different ones via union), and the parent's coercion / validation / serialization machinery walks the tree.

## Nested FieldStructs

Declare a field whose type is another `FieldStruct::Base` subclass — it's automatically wrapped in `Types::Nested`:

```ruby
class Address < FieldStruct::Base
  required :street, :string
  required :city,   :string
  required :zip,    :string
end

class Person < FieldStruct::Base
  required :name,    :string
  required :address, Address
end
```

Now `Person` accepts an `Address` instance *or* a Hash:

```ruby
Person.new(
  name: 'Alice',
  address: { street: '742 Evergreen', city: 'Springfield', zip: '97477' }
)

# Or, given an existing instance:
addr = Address.new(street: '742 Evergreen', city: 'Springfield', zip: '97477')
Person.new(name: 'Alice', address: addr)
```

The hash form constructs the nested instance via `Address.new(hash)` — same path as if you'd built it by hand.

### Errors from nested

A nested instance's invalidity propagates:

```ruby
p = Person.new(name: 'Alice', address: { street: '742', city: '', zip: '97477' })
p.valid?                  # => false
p.errors[:address]        # => ["is invalid"]
p.address.errors[:city]   # => ["can't be blank"]
```

The parent records a single `"is invalid"` for the nested field; the granular per-field messages live on the nested instance's own `errors`. That keeps the parent's error shape predictable (always a flat field → messages map) while preserving the detail.

### Anonymous nested

The nested class doesn't need a constant — an anonymous `Class.new(FieldStruct::Base)` works:

```ruby
class Order < FieldStruct::Base
  required :id, :string
  required :shipping_address, Class.new(FieldStruct::Base) {
    required :street, :string
    required :city,   :string
  }
end
```

In `Field#inspect` the anonymous class shows up as `Nested(AnonymousFieldStruct)`.

### Arrays of nested

Combine `:array` and a nested class via `of:`:

```ruby
class Cart < FieldStruct::Base
  required :customer, Customer
  required :items,    :array, of: LineItem
end
```

Each element runs through `LineItem.new(...)` (or passes through if it's already an instance).

### Serialization walks the tree

`as_json` and `to_json` recurse into nested FieldStructs and arrays of nested:

```ruby
cart.as_json
# => {
#      customer: { id: 7, name: "Alice" },
#      items: [
#        { sku: "A1", qty: 2 },
#        { sku: "B7", qty: 1 }
#      ]
#    }
```

`Klass.from_json` walks the same way in reverse — including any `serialize :json` mappings (see [Serialization](./serialization)).

## Union Types

A union field holds **one of several** types. Each member is tried in declared order; the first whose `#coerce` doesn't reject the value wins.

```ruby
class Webhook < FieldStruct::Base
  required :payload, :union, of: [String, Integer]
end

Webhook.new(payload: 'hello').payload   # => "hello"
Webhook.new(payload: 42).payload        # => 42
Webhook.new(payload: '42').payload      # => "42"   (String wins first)
```

### Order matters

`of: [String, Integer]` and `of: [Integer, String]` give different results for `"42"`:

```ruby
Webhook.new(payload: '42').payload  # => "42" with [String, Integer]
                                    # => 42   with [Integer, String]
```

Order your members from most-specific to most-general.

### Mixing FieldStructs and scalars

```ruby
class Event < FieldStruct::Base
  # A reference can be a full User payload OR just a user id string
  required :actor, :union, of: [User, :string]
end

Event.new(actor: 'u_42').actor              # => "u_42"
Event.new(actor: { id: 7, name: 'Alice' }).actor
# => #<User name: "Alice", …>
```

### What gets rejected

Union catches `ArgumentError`, `TypeError`, and `FieldStruct::Error` from each member's `coerce`. Unrelated bugs (e.g. `NoMethodError`) still propagate — only "this value isn't shaped right for me" failures get caught.

If every member rejects, the union itself raises `TypeError`, which the parent's `coercion_policy` handles like any shape-level failure.

### `ruby_type` on a Union

A union's `ruby_type` is the flat list of its members' `ruby_type`s, deduplicated:

```ruby
field = Webhook.metadata[:payload]
field.type_instance.ruby_type   # => [String, Integer]
```

This is what schema / RBS generators look at when emitting union signatures.

## Inspect output

Nested and union show up clearly in `Field#inspect`:

```ruby
Cart.metadata
# => #<FS::Metadata
#      #<FS::Field :customer Nested(Customer) required>
#      #<FS::Field :items Array of_type=Nested(LineItem) required>
#    >

Webhook.metadata[:payload]
# => #<FS::Field :payload Union(String | Integer) required>
```

## Next

- [Pattern Matching](./pattern-matching) — `case` / `in` patterns across nested trees
- [Serialization](./serialization) — `as_json` / `from_json` walk nested + arrays of nested
