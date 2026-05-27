# Field Options

Every `field` / `required` / `optional` call accepts options that tune the field's behavior. Some are universal; most are type-specific. This page is the reference.

## Universal options

These work on every field, regardless of type.

### `required:` (Boolean)

Set by the `required` / `optional` sugar; you usually don't pass it directly. A required field that's missing after construction shows up as `errors[:field] => ["can't be blank"]`.

### `default:` (literal or callable)

Applied at construction when the input hash *omits* the key. Callables are invoked once per instance:

```ruby
optional :role,       :string, default: 'member'
optional :created_at, :time,   default: -> { Time.now }
```

Passing `nil` explicitly does **not** apply the default — `nil` is what you'll get.

### `description:` / `desc:`

Human-readable documentation metadata. Lives on `Field#description`. Doesn't appear in `attributes` / `as_json` / `deconstruct_keys`. See [Defining Fields](./defining-fields#descriptions).

### `coercion_policy:`

A per-field override of the class-level `coercion_policy`. One of `:keep_raw`, `:replace`, `:raise`. See [Types & Coercion](./types-and-coercion#per-field-override).

### `enum:` (Array)

For "string-like" types (`:string`, `:symbol`, …). Restricts allowed values to a finite set after coercion:

```ruby
required :level, :string, enum: %w[beginner intermediate pro]
```

A value outside the set surfaces as a `errors[:level] => ["is not included in the list"]`.

### `in:` (Range or Array)

The "rangy" counterpart of `enum:`. Use it for numeric / date / time types:

```ruby
required :score, :integer, in: 0..100
required :born,  :date,    in: Date.new(1900, 1, 1)..Date.today
```

Out-of-range values surface as `errors[:field] => ["is not included in the list"]`.

## Per-type options

### `:string` (and family)

| Option | Type | Effect |
|--------|------|--------|
| `format:` | Regexp | Value must match the pattern. |
| `enum:` | Array | Value must be a member. |

```ruby
required :sku,   :string, format: /\A[A-Z0-9-]+\z/
required :level, :string, enum: %w[beginner pro]
```

### `:integer`

| Option | Type | Effect |
|--------|------|--------|
| `in:` | Range / Array | Value must fall inside. |

### `:float` / `:big_decimal`

| Option | Type | Effect |
|--------|------|--------|
| `round:` | Integer | Coerce then round to N decimal places. |
| `in:` | Range | Value must fall inside. |

```ruby
required :total, :big_decimal, round: 2
required :ratio, :float,       round: 4, in: 0.0..1.0
```

### `:boolean`

| Option | Type | Effect |
|--------|------|--------|
| `truthy:` | Array | Values coerced to `true`. Default includes `true`, `1`, `'true'`, `'t'`, `'yes'`, `'y'`, `'on'`. |
| `falsy:` | Array | Values coerced to `false`. Default includes `false`, `0`, `'false'`, `'f'`, `'no'`, `'n'`, `'off'`. |
| `values:` | Symbol / Hash | Pick a preset (`:default`, `:strict`) or a custom hash. |

```ruby
required :flag, :boolean, values: :strict   # only `true` / `false` accepted
```

### `:date` / `:time` / `:datetime`

| Option | Type | Effect |
|--------|------|--------|
| `format:` | strftime String, or `:iso8601`, `:rfc2822`, `:rfc3339` | Parse incoming strings with this format. |

```ruby
required :born, :date, format: :iso8601
required :at,   :time, format: '%Y-%m-%d %H:%M'
```

The symbol forms are resolved through `Types::PresetResolver` at field-declaration time, so all instances share the resolved strftime string.

### `:array`

| Option | Type | Effect |
|--------|------|--------|
| `of:` | Symbol / Class | Element type. Each element runs through that type's `coerce`. |

```ruby
required :tags,      :array, of: :string
required :addresses, :array, of: Address          # nested
required :scores,    :array, of: :integer, in: 0..100
```

Per-element options (the `in: 0..100` above) propagate to every element's coercion.

### `:union`

| Option | Type | Effect |
|--------|------|--------|
| `of:` | Array of types | Member types. Each is tried in declared order; the first that doesn't reject wins. |

```ruby
required :payload, :union, of: [String, Integer]
required :ref,     :union, of: [User, :string]   # FieldStruct member + scalar
```

Order matters. `of: [String, Integer]` coerces `"42"` to `"42"` (String wins first). `of: [Integer, String]` coerces `"42"` to `42`. See [Nested & Union Types](./nested-and-union#union-types).

### `:uuid` / `:url` / `:email`

| Option | Type | Effect |
|--------|------|--------|
| `format:` | Regexp | Custom validation pattern (overrides the default). |

```ruby
required :email, :email, format: /\A.+@example\.com\z/i
```

### `:binary`

No options. Stores bytes as ASCII-8BIT.

## Combining options

Most options stack:

```ruby
required :score,   :integer, in: 0..100, default: 0,
                              description: 'Test score (0–100)'

required :tags,    :array, of: :string,
                              description: 'Free-form tags'

required :created, :date, format: :iso8601, default: -> { Date.today }
```

Conflicting options on a single field — e.g. both `description:` and `desc:` — raise `ArgumentError` at class-definition time, not at instance construction.

## Next

- [Validation](./validation) — the `validate` macro for cross-field rules
- [Nested & Union Types](./nested-and-union) — composing FieldStructs and multi-type fields
