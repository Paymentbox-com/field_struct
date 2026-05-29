# FieldStruct — usage reference

Dense, example-first reference for using the `field_struct` gem. Optimized for an
agent (or human) to load once and use the whole API correctly. For narrative
docs see `README.md`; for design rationale see `docs/origin/plan.md`.

**Mental model:** declare fields on a `FieldStruct::Base` subclass. Each field
gets a coerced, typed reader/writer and presence/format validation. Construction
and validity are *separate* — you can build an invalid instance; ask `valid?`.

<!-- doctest -->
```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
end

u = User.new(name: 'Alice', age: '30') # string + symbol keys both work
u.name        # => "Alice"
u.age         # => 30
u.attributes  # => { name: "Alice", age: 30 }
u.valid?      # => true
```

---

## Types

Register name in the first column; use it as the second arg to `field`/`required`/
`optional`. "Coerces from" is what the setter accepts (`nil` always passes through
as `nil`). "Missing" is what counts as absent for presence checks.

| Name | Ruby type | Coerces from | Type options | Missing when |
|------|-----------|--------------|--------------|--------------|
| `:string` | `String` | `value.to_s` | `format:`, `enum:` | nil / empty / whitespace-only |
| `:immutable_string` | `String` (frozen) | `to_s`, then frozen dup | `format:`, `enum:` | nil / empty / whitespace |
| `:integer` | `Integer` | `Kernel.Integer` (floats truncate; `"3.14"`/non-digits raise) | `in:` | nil |
| `:float` | `Float` | `Kernel.Float` (strict) | `round:`, `in:` | nil |
| `:big_decimal` (alias `:decimal`) | `BigDecimal` | BigDecimal/Integer/Float/numeric string | `round:`, `in:` | nil |
| `:boolean` | `true`/`false` | `true`/`false`, `1`/`0`, truthy/falsy strings | `values:` | nil |
| `:date` | `Date` | `Date`, `#to_date`, String (parse/strptime) | `format:`, `in:` | nil |
| `:time` | `Time` | `Time`, `#to_time`, String | `format:`, `in:` | nil |
| `:datetime` | `DateTime` | `DateTime`, `#to_datetime`, String | `format:`, `in:` | nil |
| `:symbol` | `Symbol` | `Symbol`, `String#to_sym` (else `TypeError`) | `enum:` | nil |
| `:uuid` | `String` | `to_s` | `format:` (`:any_version`/`:v4`/`:v7`), `enum:` | nil / empty / whitespace |
| `:url` | `String` | `to_s` | `format:` (`:http`/`:https_only`/`:any_scheme`), `enum:` | nil / empty / whitespace |
| `:email` | `String` | `to_s` | `format:` (`:permissive`/`:default`/`:strict`), `enum:` | nil / empty / whitespace |
| `:binary` | `String` (ASCII-8BIT) | `to_s`, forced to binary encoding | — | nil / empty (**whitespace bytes are kept**) |
| `:value` | `Object` (untyped) | pass-through, no coercion | — | nil |
| `:array` | `Array` | each element coerced through `of:` | `of:` (**required**) | nil / empty |
| `:union` | first matching member | tries each member type | `of:` (**Array, ≥2**) | nil |
| nested (a `FieldStruct::Base` subclass) | that class | Hash → instance, or instance | — | nil |

```ruby
required :id,        :uuid, format: :v4
required :website,   :url,  format: :https_only
optional :email,     :email                       # default regex
required :status,    :symbol, enum: %i[active archived]
required :score,     :integer, in: 0..100
required :price,     :big_decimal, round: 2
optional :tags,      :array, of: :string
required :ref,       :union, of: %i[string integer]
optional :address,   Address                       # nested FieldStruct
optional :lines,     :array, of: LineItem          # array of nested
```

---

## Field options (any type)

| Option | Meaning |
|--------|---------|
| `required: true` | presence-checked (`required :x` is sugar; `optional :x` / bare `field :x` are not) |
| `default:` | literal, **or** a callable (`-> { Time.now }`, a Proc/Method) invoked once per instance |
| `coercion_policy:` | `:keep_raw` (default) \| `:replace` \| `:raise` — per-field override of the class setting |
| `description:` / `desc:` | human text; introspection only — **never** in `attributes`/`as_json`/pattern match |

```ruby
class Account < FieldStruct::Base
  required :id,         :uuid, default: -> { SecureRandom.uuid }, desc: 'primary key'
  optional :balance,    :big_decimal, default: 0, coercion_policy: :raise
end
```

Type-specific options: `format:` (string-shaped + date/time/datetime — a regex or a
strftime string or a preset Symbol), `round:` (float/decimal — Integer places),
`values:` (boolean — a `{truthy:, falsy:}` Hash or a preset Symbol), `of:` (array
element type / union member array), `enum:` (string-like — Array of allowed values),
`in:` (numeric/temporal — Array or Range).

```ruby
required :joined, :date, format: '%m/%d/%Y'   # custom strftime
required :paid,   :boolean, values: :english_yes_no
required :flag,   :boolean, values: { truthy: %w[on], falsy: %w[off] }
```

Boolean presets: `:english_yes_no`/`:english` (`true yes y on 1` / `false no n off 0`),
`:numeric` (`1`/`0`). Date presets: `:iso8601 :us :eu`. Time/DateTime presets:
`:iso8601 :rfc2822 :db`.

---

## Class macros

```ruby
class Doc < FieldStruct::Base
  immutable!                    # setters raise ImmutableError after initialize
  frozen!                       # Ruby-freeze the instance at end of initialize (stackable with immutable!)
  coercion_policy :replace      # class-wide coercion-failure policy; inherited by subclasses
  unknown_attributes :raise     # reject unknown input keys (default :ignore = drop them)

  required :title, :string
  required :slug,  :string

  serialize :json, title: 'docTitle'   # map internal field -> external JSON key (:json wired in)

  validate :slug_matches_title         # cross-field validator (method symbol)
  validate { |rec| rec.errors.add(:base, 'empty') if rec.title.to_s.empty? }  # or block

  def slug_matches_title
    errors.add(:base, 'slug/title mismatch') unless slug == title.downcase
  end
end
```

- `coercion_policy` / `unknown_attributes` are read with no arg, set with one.
- **Inheritance:** all four macros inherit to subclasses; a child overrides by re-declaring, and the override never mutates the parent. `coercion_policy`/`unknown_attributes` override to any value; `immutable!`/`frozen!` are **one-way** — a child can add them but can't un-set an inherited one (no `mutable!`/`unfrozen!`).
- `validate` runs at `valid?` (and at construct if any exist); convention is `errors.add(:base, ...)`; `errors[:base]` is cleared each `valid?` run.

---

## Instance surface

```ruby
u = User.new(name: 'Alice', age: '30')   # Hash arg; Symbol or String keys
u.name; u.age = 31                        # typed reader; permissive setter (coerces)
u.attributes        # => { name: "Alice", age: 31 }   (alias: to_h)
u.attribute_names   # => [:name, :age]
u.valid?            # runs cross-field validators, then errors.empty?
u.invalid?
u.errors            # FieldStruct::Errors
u == other          # value equality (same class + same attributes; errors ignored)
u.as_json           # JSON-ready Hash with :json mapping applied
u.to_json           # String (via Oj)
User.from_json(str) # parse + reverse-map :json keys -> instance
u.assign_attributes(age: 40)              # bulk update through the setter pipeline
case u; in { name: 'Alice', age: } then age; end   # pattern matching
```

`Errors` API: `errors[:field] # => Array<String>`, `errors.add(:field, 'msg')`,
`errors.clear(:field)`, `errors.empty?`, `errors.to_h` (alias `messages`).

---

## Validation semantics (important)

- **Per-field, on every assignment.** The setter owns its field's errors — it clears
  and rewrites `errors[name]` each time you assign.
- **Required + missing** → `errors.add(name, 'is required')`.
- **Present but invalid** → `errors.add(name, 'is invalid')`. "Invalid" = `format:`
  regex mismatch, `enum:`/`in:` violation, an invalid nested struct, or an array with
  an invalid element. So **"required" means present *and* valid**.
- **Validity is separate from construction.** A field can hold `nil`/raw even when
  required — see coercion policy below. Always gate on `valid?`, don't assume a
  required reader is non-nil.

### Coercion failure policy

When a value can't be coerced into the field's type:

| Policy | Stored value | Error added | Notes |
|--------|--------------|-------------|-------|
| `:keep_raw` (default) | the raw input | yes (`could not be coerced: …`) | nothing lost; inspect & fix |
| `:replace` | `nil` | yes | clean slate |
| `:raise` | — | — | raises `FieldStruct::CoercionError` |

---

## Nested, arrays, unions

```ruby
class Address < FieldStruct::Base
  required :city, :string
end

class Person < FieldStruct::Base
  required :name,    :string
  optional :address, Address                 # nested: Hash or Address instance
  optional :aliases, :array, of: :string      # array of scalars
  optional :homes,   :array, of: Address       # array of nested (each coerced + validated)
  required :id,      :union, of: %i[string integer]   # union: first member that accepts it
end

Person.new(name: 'A', address: { city: 'NYC' }).address   # => #<Address city: "NYC">
```

Nested validity propagates: a `Person` with an invalid `address` is itself invalid.
Pattern matching recurses (`in { address: { city: 'NYC' } }`).

---

## JSON & serialization

- `as_json`/`to_json` apply the `:json` `serialize` mapping (forward); `from_json`
  reverse-maps. Round-trips for every base type **except `:value`** (no type info to
  restore).
- Conversions in `as_json`: `Date`/`Time`/`DateTime` → ISO-8601 (or the field's
  `format:`), `BigDecimal` → plain string, `Symbol` → String, arrays/nested recurse.

<!-- doctest -->
```ruby
class U < FieldStruct::Base
  required :first, :string
  serialize :json, first: 'firstName'
end
U.new(first: 'Al').to_json          # => '{"firstName":"Al"}'
U.from_json('{"firstName":"Al"}')   # => #<U first: "Al">
```

---

## Custom types & namespaces

A namespace exposes `self.field_types` (a registry parented to the base set); fields
declared on classes inside that namespace resolve names through it.

```ruby
module Acme
  def self.field_types
    @field_types ||= FieldStruct.new_registry do   # parent defaults to FieldStruct.types
      register :money, Acme::Types::Money           # add a type
      register :dec,   :big_decimal                 # alias to an existing name
    end
  end

  class Invoice < FieldStruct::Base
    required :total, :money     # resolved via Acme.field_types
  end
end
```

A custom type is a `FieldStruct::Types::Base` subclass implementing `#coerce` and
`#ruby_type` (override `#missing?` for a broader notion than nil-only).

Optional short alias: `FieldStruct.use_alias!(:FS)` defines top-level `FS` →
`FieldStruct` and switches inspect output to the short prefix.

---

## Introspection

```ruby
User.metadata            # => #<FieldStruct::Metadata fields=[:name, :age]>
User.metadata[:age]      # => #<FieldStruct::Field :age Integer>
User.attribute_names     # => [:name, :age]
field = User.metadata[:age]
field.name; field.type; field.required?; field.default; field.options; field.type_instance.ruby_type
```

---

## RBS for your own classes

Sord types the library; `FieldStruct::RBS.generate` types the accessors **your**
`field` declarations create, so Steep/Solargraph can check `user.name`:

```ruby
puts FieldStruct::RBS.generate(User)
# class User < ::FieldStruct::Base
#   attr_reader name: ::String
#   def name=: (untyped value) -> untyped
#
#   attr_reader age: ::Integer?
#   def age=: (untyped value) -> untyped
# end
```

Reader = the field's Ruby type; nullability follows `required?` (required → `T`,
optional → `T?`). Setter is `untyped` because coercion accepts loose input. Generate
RBS for nested/element classes too so `::Address` references resolve. See the README
"Type signatures" section for a Rake-task wiring example.

---

## Gotchas / invariants

- **Setters are permissive by design** — `user.age = "30"` is valid (coerces). The
  reader is typed; the writer accepts `untyped`.
- **A required field can still be `nil`** (coercion failed under `:keep_raw`/`:replace`,
  or never assigned). Check `valid?`; don't assume required ⇒ non-nil.
- **Whitespace-only strings are "missing"** for `:string` and its subclasses
  (`:uuid`/`:url`/`:email`/`:immutable_string`). `:binary` is the exception — its
  whitespace bytes are real data, so only nil/empty count as missing.
- **`nil` passes through coercion as `nil`** for essentially every type.
- `:array` requires `of:`; `:union` requires `of: [...]` with ≥2 members.
- Option scoping: `format:` → string-shaped + date/time/datetime; `enum:` →
  string/symbol; `in:` → integer/float/decimal/date/time/datetime; `round:` →
  float/decimal; `values:` → boolean. Misapplying raises `ArgumentError` at declaration.
- `description:`/`desc:` is documentation only — absent from `attributes`, `as_json`,
  and pattern-match keys.
- Unknown input keys are dropped by default (`unknown_attributes :ignore`); set
  `:raise` to reject them with `UnknownAttributeError`.
- Uses **Oj** for JSON (`Oj.load`/`Oj.dump`), not the stdlib JSON.
