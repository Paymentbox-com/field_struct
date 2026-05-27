# Getting Started

FieldStruct is a Ruby library for building **Plain Old Ruby Objects** with declared attributes that have enforced types, coercion, presence checks, and validation. It is *not* a database layer, form object, or ActiveModel replacement — it mirrors AM's interface shape in places but reuses none of its code.

## Requirements

- Ruby **3.0+**
- No runtime dependencies on Rails or ActiveSupport. The only runtime dep is [Oj](https://github.com/ohler55/oj) for JSON.

## Install

Add to your `Gemfile`:

```ruby
gem 'field_struct'
```

Then:

```bash
bundle install
```

Or system-wide:

```bash
gem install field_struct
```

## Your first FieldStruct

```ruby
require 'field_struct'

class User < FieldStruct::Base
  required :name,  :string
  required :email, :string,  format: /@/
  optional :age,   :integer, default: 0
end
```

That's it. You now have a class with:

- Three declared fields (`name`, `email`, `age`), each typed.
- A keyword constructor.
- Per-field getters and setters that coerce on assignment.
- Per-field error tracking.
- `attributes` / `to_h` / `as_json` / `to_json` for export.
- Pattern-matching support via `deconstruct_keys`.

## Using it

```ruby
user = User.new(name: 'Alice', email: 'alice@example.com', age: '30')

user.name          # => "Alice"
user.age           # => 30                    # coerced from "30"
user.attributes    # => { name: "Alice", email: "alice@example.com", age: 30 }
user.valid?        # => true
user.errors.empty? # => true
```

If you give it bad input, the error lives on the instance — the constructor does not raise (the default `coercion_policy` is `:keep_raw`, see [Types & Coercion](./types-and-coercion)):

```ruby
bad = User.new(name: 'Alice', email: 'not-an-email')
bad.valid?         # => false
bad.errors[:email] # => ["is invalid"]
```

A missing required field is also surfaced as an error, not an exception:

```ruby
incomplete = User.new(name: 'Alice')
incomplete.valid?         # => false
incomplete.errors[:email] # => ["can't be blank"]
```

## Inspecting a class

Every class collects its declarations into a `Metadata` object you can introspect:

```ruby
User.metadata
# => #<FieldStruct::Metadata
#      #<FieldStruct::Field :name String required>
#      #<FieldStruct::Field :email String required format=/@/>
#      #<FieldStruct::Field :age Integer default=0>
#    >

User.metadata.names    # => [:name, :email, :age]
User.metadata[:email]  # => #<FieldStruct::Field :email String required format=/@/>
```

In IRB, `Field` and `Metadata` use custom `#inspect` / `#pretty_print` so they don't dump every ivar. See [Defining Fields](./defining-fields).

## A nicer IRB prefix (optional)

`FieldStruct::` everywhere can get long. The library ships an opt-in alias:

```ruby
FieldStruct.use_alias!
# Defines a top-level `FS` constant pointing back to FieldStruct, *and*
# swaps the prefix used by every #inspect across the library.

FS::Base
# => FieldStruct::Base

User.metadata.inspect
# => "#<FS::Metadata fields=[:name, :email, :age]>"
```

Off by default — opt in only if you want it.

## Where to go next

- [Defining Fields](./defining-fields) — `required` / `optional` / defaults / descriptions
- [Types & Coercion](./types-and-coercion) — the built-in types and how coercion works
- [Validation](./validation) — the `validate` macro and per-field errors
- [Nested & Union Types](./nested-and-union) — composing FieldStructs
- [Serialization](./serialization) — JSON in / JSON out
