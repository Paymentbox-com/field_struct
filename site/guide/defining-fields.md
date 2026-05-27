# Defining Fields

Every FieldStruct class declares its attributes with one of three macros: `field`, `required`, and `optional`. They all build the same underlying `Field` object — `required` and `optional` are sugar for the most common cases.

## The macros

```ruby
class User < FieldStruct::Base
  # The general form:
  field :name, :string, required: true

  # Sugar:
  required :email, :string                 # field(..., required: true)
  optional :age,   :integer, default: 0    # field(..., required: false)
end
```

`required` and `optional` are identical to `field` apart from defaulting `required:` to `true` / `false`. Use them — the intent reads better at the call site.

## The shape of a field declaration

```ruby
required :name, :type_or_class, **options
```

| Argument | Meaning |
|----------|---------|
| `name` | The attribute name, a Symbol (or String — coerced to Symbol). |
| `type_or_class` | A type. Either a registered symbol like `:string`, a `Types::Base` subclass, or another `FieldStruct::Base` subclass (which is auto-wrapped as `Types::Nested`). |
| `options` | Field-level options. The exact keys depend on the type — see [Field Options](./field-options) for the full reference. |

The macros return the class-level **Metadata** (not the just-added Field), so the DSL block reads well in IRB:

```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age, :integer
end
# => #<FS::Metadata
#      #<FS::Field :name String required>
#      #<FS::Field :age Integer>
#    >
```

The just-added Field is still available via `metadata[:name]`.

## Defaults

`default:` accepts a literal value or a parameterless callable.

```ruby
class User < FieldStruct::Base
  optional :role,      :string,  default: 'member'
  optional :created_at, :time,   default: -> { Time.now }
  optional :uuid,       :uuid,   default: -> { SecureRandom.uuid }
end
```

Callable defaults are invoked **once per instance** during construction. The default is only applied when the input hash *omits* the key — if you pass `nil` explicitly, that nil is what you'll get (subject to coercion).

## Descriptions

Every field can carry a `description:` (or its short alias `desc:`). This is documentation metadata — it never appears in `attributes`, `as_json`, or pattern-matching output. It's there for downstream tooling (docs generators, schema exporters):

```ruby
class User < FieldStruct::Base
  required :email, :string, format: /@/,
                            description: 'Primary contact email — used for password resets'
  required :role,  :string, desc: 'One of "admin", "member", "viewer"'
end

User.metadata[:email].description
# => "Primary contact email — used for password resets"
```

Passing both `description:` and `desc:` is an error — pick one.

## Inheritance

Subclasses inherit their parent's fields. Re-declaring a field in the child replaces the parent declaration (child wins on conflict):

```ruby
class Person < FieldStruct::Base
  required :name, :string, description: 'parent says'
end

class Employee < Person
  required :name, :string, description: 'child says'  # overrides
  required :role, :string
end

Employee.metadata.names
# => [:name, :role]

Employee.metadata[:name].description
# => "child says"

Person.metadata[:name].description
# => "parent says"   # parent is untouched
```

A child that re-declares a field **without** `description:` drops the inherited description — re-declaration is a fresh declaration, not an extend.

## Introspecting Metadata

`klass.metadata` is `Enumerable`. Walk it like any collection:

```ruby
User.metadata.each do |field|
  puts "#{field.name}: #{field.type} (#{field.required? ? 'required' : 'optional'})"
end
```

Or build a quick documentation table:

```ruby
User.metadata.map { |f| [f.name, f.type.name.split('::').last, f.description] }
# => [
#      [:name, "String", nil],
#      [:email, "String", "Primary contact email …"],
#      [:role, "String", 'One of "admin", "member", "viewer"']
#    ]
```

## What `Field` carries

Each `Field` exposes:

| Reader | Meaning |
|--------|---------|
| `#name` | Canonical Symbol name |
| `#type` | Resolved type class (`FieldStruct::Types::String`, etc.) |
| `#type_instance` | Pre-built type instance (parameterized for `Nested` / `Union` / `Array`) |
| `#required?` | Whether presence is enforced |
| `#default` | The default literal or callable, or `nil` |
| `#description` (alias `#desc`) | Human-readable description, or `nil` |
| `#coercion_policy` | Per-field policy override, or `nil` to defer to the class |
| `#options` | The remaining type-specific options as a frozen Hash |

Fields are **frozen** after construction — the DSL builds a fresh Field rather than mutating one.

## Next

- [Types & Coercion](./types-and-coercion) — what `:string`, `:integer`, `:date`, … actually do
- [Field Options](./field-options) — the full reference for `enum:`, `in:`, `format:`, `round:`, `of:`, …
