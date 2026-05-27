# Pattern Matching

Every FieldStruct instance implements Ruby's pattern-matching protocol — `deconstruct_keys` for `{ }` patterns and `deconstruct` for `[ ]` patterns. `case / in` works out of the box, including across nested FieldStructs.

## Hash patterns (`deconstruct_keys`)

```ruby
class User < FieldStruct::Base
  required :name,  :string
  required :email, :string
  optional :role,  :string, default: 'member'
end

user = User.new(name: 'Alice', email: 'alice@example.com', role: 'admin')

case user
in { role: 'admin', email: }
  puts "admin: #{email}"
in { role: 'member' }
  puts "regular user"
end
```

`deconstruct_keys(nil)` returns every declared field; passing an array of names slices down to those keys:

```ruby
user.deconstruct_keys(nil)              # => { name: "Alice", email: "...", role: "admin" }
user.deconstruct_keys(%i[role email])   # => { role: "admin", email: "..." }
```

Only **canonical** field names participate. Aliases (per the field-name aliases feature) and descriptions are not exposed via pattern matching.

## Array patterns (`deconstruct`)

```ruby
case user
in [name, email, _]
  puts "#{name} <#{email}>"
end
```

`deconstruct` returns field values in declaration order — the same order they appear in `Metadata#names`.

## Nested patterns

Nested FieldStructs respond to the same protocol, so deep patterns just work:

```ruby
class Address < FieldStruct::Base
  required :city,  :string
  required :state, :string
end

class Person < FieldStruct::Base
  required :name,    :string
  required :address, Address
end

p = Person.new(name: 'Alice', address: { city: 'NYC', state: 'NY' })

case p
in { address: { city: 'NYC' } }
  puts "New Yorker"
in { address: { state: } }
  puts "From #{state}"
end
```

The match descends as far as the pattern asks — no extra setup needed in the FieldStruct classes.

## Type / class patterns

The standard `=>` binding works with Ruby's type patterns:

```ruby
case user
in { name: String => name, role: 'admin' }
  notify_admin(name)
end
```

`String =>` checks the class of the matched value, then binds it.

## Arrays of nested

Pattern-match through arrays of FieldStructs:

```ruby
cart = Cart.new(items: [{ sku: 'A1', qty: 2 }, { sku: 'B7', qty: 1 }])

case cart
in { items: [{ sku: 'A1' }, *] }
  puts "starts with the A1"
end
```

## Find patterns

Ruby's find pattern (`[*, x, *]`) lets you ask "is there an item like this somewhere":

```ruby
case cart
in { items: [*, { sku: 'B7' }, *] }
  puts "contains a B7"
end
```

## Combining with `valid?`

Pattern matching doesn't run validation — it just looks at the current attribute values. Pair it with `valid?` when both shape and validity matter:

```ruby
case user
in User => u if u.valid? && u.role == 'admin'
  promote(u)
end
```

## Why this matters

Pattern matching turns a FieldStruct into a structured value you can branch on the way you would a Struct, but with coercion + validation already done. It pairs particularly well with:

- Routing-style dispatch on incoming payloads
- Read models in command/query separation
- Test assertions on rich objects

## Next

- [Serialization](./serialization) — JSON in / JSON out (including from a payload received from an external system)
- [Class Macros](./class-macros) — `immutable!` / `frozen!` for instances you've promoted to "settled"
