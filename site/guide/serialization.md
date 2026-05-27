# Serialization

FieldStruct ships first-class JSON I/O. Export to a hash, to a JSON string, or read JSON back into an instance — recursively through nested FieldStructs and arrays of nested.

## The four output surfaces

| Method | Returns | When to use |
|--------|---------|-------------|
| `#attributes` (aliased `#to_h`) | Hash of canonical names → raw values | Ruby-side handoff |
| `#as_json([options])` | Hash, JSON-ready | Building API payloads |
| `#to_json([options])` | String (via Oj) | Writing to the wire |
| `#deconstruct_keys(nil)` | Hash | Pattern matching (see [Pattern Matching](./pattern-matching)) |

`#attributes` returns values *as Ruby objects* — Time stays a Time, BigDecimal stays a BigDecimal. `#as_json` canonicalizes for JSON:

| Ruby value | `as_json` becomes |
|------------|-------------------|
| `Date` / `Time` / `DateTime` | ISO-8601 String |
| `BigDecimal` | plain-form String (`"19.95"`) |
| `Symbol` | String |
| `Array` | recursive map |
| Nested `FieldStruct` | recursive `as_json` |

```ruby
class Order < FieldStruct::Base
  required :id,         :string
  required :total,      :big_decimal, round: 2
  required :placed_at,  :time
  required :line_items, :array, of: LineItem
end

o = Order.new(id: 'o_1', total: '19.99', placed_at: Time.utc(2026,5,27,12,0), line_items: [...])

o.attributes
# => { id: "o_1", total: #<BigDecimal …>, placed_at: 2026-05-27 12:00 UTC, line_items: [#<LineItem …>] }

o.as_json
# => { id: "o_1", total: "19.99", placed_at: "2026-05-27T12:00:00Z", line_items: [{...}, ...] }

o.to_json
# => '{"id":"o_1","total":"19.99","placed_at":"2026-05-27T12:00:00Z","line_items":[…]}'
```

## The `serialize` macro

External systems rarely match your Ruby naming. The `serialize` macro declares a per-format **rename map** from internal field names (Symbol) to external names (String):

```ruby
class User < FieldStruct::Base
  required :first_name, :string
  required :last_name,  :string
  required :email,      :string

  serialize :json, first_name: 'firstName', last_name: 'lastName'
end
```

`as_json` and `to_json` apply the map on the way out:

```ruby
u = User.new(first_name: 'Alice', last_name: 'Liddell', email: 'alice@example.com')

u.as_json
# => { firstName: "Alice", lastName: "Liddell", email: "alice@example.com" }
```

Fields not listed in the map serialize under their canonical name (`email` above).

The mapping is **frozen** when registered. Repeats on the same format name replace the prior mapping (last-write-wins). Subclasses inherit their parent's mappings; child declarations win on conflict.

### Why a separate `serialize :json`?

Because `serialize` is the I/O boundary, not the value boundary. The canonical field name (`first_name`) stays the contract inside your code; the external `firstName` is wire format. A schema change on the outside doesn't ripple through your Ruby code.

You can declare multiple formats:

```ruby
class User < FieldStruct::Base
  required :first_name, :string

  serialize :json,    first_name: 'firstName'
  serialize :legacy,  first_name: 'firstname'   # for an older API
end
```

Right now only the `:json` mapping is consumed by `as_json` / `from_json`; other format names sit in metadata for future / custom serializers.

## Reading JSON back in

`Klass.from_json` parses a JSON string (via Oj), reverses any `serialize :json` mapping, and constructs an instance — recursively through nested FieldStructs and arrays of nested:

```ruby
json = '{"firstName":"Alice","lastName":"Liddell","email":"alice@example.com"}'

User.from_json(json)
# => #<User first_name: "Alice", last_name: "Liddell", email: "alice@example.com">
```

`from_json` walks nested classes too — each nested field's class is consulted for its own `serialize :json` map. The same applies to arrays of nested.

### Errors during import

Coercion / validation runs as normal. The returned instance's `errors` carries whatever didn't fit:

```ruby
User.from_json('{"email":"no-at"}').errors.to_h
# => { first_name: ["can't be blank"], last_name: ["can't be blank"], email: ["is invalid"] }
```

If you want hard failure on bad input, pair with `coercion_policy :raise` (see [Class Macros](./class-macros)).

## Nested + array recursion

A worked example. Given:

```ruby
class Address < FieldStruct::Base
  required :city,  :string
  required :state, :string
  serialize :json, city: 'cityName'
end

class Person < FieldStruct::Base
  required :name,      :string
  required :addresses, :array, of: Address
  serialize :json, name: 'fullName'
end
```

Output round-trips through both mappings:

```ruby
p = Person.new(
  name: 'Alice',
  addresses: [{ city: 'NYC', state: 'NY' }, { city: 'SF', state: 'CA' }]
)

p.as_json
# => {
#      fullName: "Alice",
#      addresses: [
#        { cityName: "NYC", state: "NY" },
#        { cityName: "SF", state: "CA" }
#      ]
#    }

Person.from_json(p.to_json) == p   # true (by attribute equality)
```

## Oj, not JSON

FieldStruct uses [Oj](https://github.com/ohler55/oj) under the hood — faster, more predictable than the stdlib `JSON`. If you need to interop with code that calls `JSON.parse` / `to_json` directly: `Klass#as_json` returns a Hash and is compatible with whatever JSON library you point at it. Use `to_json` from FieldStruct when *it* owns the serialization step.

## Next

- [Class Macros](./class-macros) — `coercion_policy`, `immutable!`, `frozen!`, `unknown_attributes`
- [Pattern Matching](./pattern-matching) — matching against received payloads
