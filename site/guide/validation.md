# Validation

FieldStruct validates **continuously**, not just at construction. Every setter runs the same pipeline and rewrites that field's entry on `instance.errors`. By the time you call `valid?`, the answer is already known — no separate "validate!" pass needs to happen.

## Automatic checks

For every assignment, the field's setter runs:

1. **Coercion** — if the value can't be coerced, the active `coercion_policy` decides what happens (see [Types & Coercion](./types-and-coercion#coercion-policy)).
2. **Presence** — for required fields, a missing value (per the type's `#missing?`) becomes `"can't be blank"`.
3. **Format** — `format:` (Regexp) mismatch becomes `"is invalid"`.
4. **Enum / In** — `enum:` / `in:` mismatch becomes `"is not included in the list"`.

```ruby
class User < FieldStruct::Base
  required :email, :string, format: /@/
  required :age,   :integer, in: 0..120
end

u = User.new(email: 'no-at', age: 200)
u.valid?            # => false
u.errors[:email]    # => ["is invalid"]
u.errors[:age]      # => ["is not included in the list"]
```

Reassigning a valid value clears that field's error:

```ruby
u.email = 'fine@example.com'
u.errors[:email]    # => []
```

## The `errors` object

Each instance has its own `FieldStruct::Errors`, behaving roughly like ActiveModel's but reusing none of its code:

```ruby
u.errors             # => #<FS::Errors email=["is invalid"] age=["is not included in the list"]>
u.errors[:email]     # => ["is invalid"]
u.errors.empty?      # => false
u.errors.to_h        # => { email: ["is invalid"], age: ["is not included in the list"] }
```

`errors.to_h` skips fields with empty message lists, so it's safe to ship as an API response payload.

## The `validate` macro

For rules that don't fit on a single field — cross-field checks, business rules — declare a `validate`:

```ruby
class TripBooking < FieldStruct::Base
  required :start_date, :date
  required :end_date,   :date

  validate do
    if start_date && end_date && end_date < start_date
      errors.add(:end_date, 'must be after start_date')
    end
  end
end
```

A `validate` block is evaluated **in the instance scope** at the end of every assignment, so cross-field invariants get re-checked when *any* field they reference changes.

### Block vs symbol form

Two equivalent shapes:

```ruby
class Order < FieldStruct::Base
  required :total,     :big_decimal
  required :discount,  :big_decimal, default: 0

  # Block form — anonymous
  validate do
    if discount && total && discount > total
      errors.add(:discount, "can't exceed total")
    end
  end

  # Symbol form — calls the named method
  validate :check_discount_makes_sense

  private

  def check_discount_makes_sense
    return unless total && discount

    errors.add(:discount, 'must be non-negative') if discount < 0
  end
end
```

Block form keeps the rule next to where it logically belongs; symbol form is the better choice when the rule is long enough to want its own method.

### Multiple validates

Declare as many as you need — they run in declaration order, each gets a chance to add errors:

```ruby
class Request < FieldStruct::Base
  required :path, :string

  validate :must_start_with_slash
  validate :must_not_have_double_slashes

  private

  def must_start_with_slash
    errors.add(:path, 'must start with /') unless path.to_s.start_with?('/')
  end

  def must_not_have_double_slashes
    errors.add(:path, "must not contain '//'") if path.to_s.include?('//')
  end
end
```

### Inheritance

`validate` declarations are inherited and merged into the subclass — parent rules still run for a child:

```ruby
class Animal < FieldStruct::Base
  required :name, :string
  validate { errors.add(:name, 'must be capitalized') unless name =~ /\A[A-Z]/ }
end

class Dog < Animal
  required :breed, :string
  validate { errors.add(:breed, 'too short') if breed.to_s.length < 3 }
end

Dog.new(name: 'rex', breed: 'a').errors.to_h
# => { name: ["must be capitalized"], breed: ["too short"] }
```

## `valid?` and `invalid?`

```ruby
order = Order.new(total: 100, discount: 150)
order.valid?    # => false  (the validate block recorded an error)
order.invalid?  # => true
```

`valid?` is idempotent and cheap — `errors` is already populated. There's no separate "go run validation" step.

## Validation context

There is **no** validation context (`:on => :create`-style). FieldStruct is for value objects, not record persistence: every check should apply at every moment. If you need create-vs-update semantics, that belongs at a layer above the value object — typically in your service / interactor / controller, where you can introspect the FieldStruct's state explicitly.

## Errors in nested structures

Validation **propagates** through nested FieldStructs: a nested instance's invalidity surfaces under the parent field. See [Nested & Union Types](./nested-and-union#errors-from-nested).

## Next

- [Nested & Union Types](./nested-and-union) — composing FieldStructs
- [Class Macros](./class-macros) — `coercion_policy`, `immutable!`, `frozen!`, `unknown_attributes`
