# Getting started with FieldStruct

How to use FieldStruct in a repo — productively, in about ten minutes. FieldStruct
builds typed POROs: you declare fields, and get coerced, typed accessors plus
presence/format validation. Construction and validity are **separate** — you can
build an invalid instance and ask it `valid?`.

This is the task-oriented adoption guide. For the exhaustive list of types and
options see [`USAGE.md`](../USAGE.md); for the feature tour see
[`README.md`](../README.md).

## At a glance — task → API

| You want to… | Do this |
|---|---|
| Declare a presence-checked field | `required :name, :string` |
| Declare a typed but optional field | `optional :age, :integer` |
| Parse an inbound webhook / JSON body | `Payload.from_json(json_string)` |
| Map external camelCase keys | `serialize :json, snake_name: 'camelName'` |
| Render to JSON | `struct.to_json` / `struct.as_json` |
| Nest a struct | `required :address, Address` |
| A list of things | `required :items, :array, of: LineItem` |
| Bootstrap a model from a sample payload | `FieldStruct::Scaffold.from_json(json)` |
| See an existing model's shape | `pp Klass.metadata.to_h` |
| Generate RBS for your models | `FieldStruct::RBS.generate(Klass)` |

## Install

```ruby
# Gemfile
gem 'field_struct'
```

```ruby
require 'field_struct' # already loaded for you in a Bundler-managed app
```

---

## Part 1 — Any Ruby project

### Your first model

<!-- doctest -->
```ruby
class User < FieldStruct::Base
  required :name, :string
  optional :age,  :integer
end

u = User.new(name: 'Alice', age: '30') # Symbol or String keys both work
u.age          # => 30
u.valid?       # => true
u.attributes   # => { name: "Alice", age: 30 }
```

`required` presence-checks the field; `optional` (and bare `field`) don't. The value
is coerced through the type — note `'30'` became `30`.

### Start fast from an existing payload

Modeling an external API or webhook? Don't hand-write the class — scaffold a starter
from a sample and refine it. It's a **prototype you finish**, not a finished model.

<!-- doctest -->
```ruby
src = FieldStruct::Scaffold.from_json('{"id": 1, "active": true, "ref": "00421"}')
src.include?('required :id, :integer')      # => true
src.include?('required :active, :boolean')  # => true
src.include?('required :ref, :string')      # => true
```

It's conservative on purpose: real JSON booleans/numbers get typed; **strings stay
`:string`** (a numeric-looking `"00421"` must not silently become an Integer), with a
trailing `# …` comment nudging you. Objects become nested classes, arrays become
`:array, of: …`. Pass an **array of same-shape objects** to get more signal — empty
fields resolve from samples that have them, presence drives `required`/`optional`, and
small repeated vocabularies surface as `# values: [...] — enum?` hints.

Then you add the things no tool can infer: enums, `required`, `description:`, formats,
and final scalar types — the comments point at where.

### Where files go

One class per file; name the file after the class. In a plain Ruby project, put them
under `lib/` and `require` them (FieldStruct uses explicit requires, no autoloading):

```
lib/
  payments/
    webhook_payload.rb   # class Payments::WebhookPayload < FieldStruct::Base
    line_item.rb         # class Payments::LineItem < FieldStruct::Base
```

Declare a nested/element class **before** the class that references it.

### Reading and writing JSON

`serialize :json` maps internal field names to external keys; `from_json` reverse-maps
on the way in, `as_json`/`to_json` forward-map on the way out.

<!-- doctest -->
```ruby
class Charge < FieldStruct::Base
  required :amount, :integer
  optional :note,   :string
  serialize :json, amount: 'amountCents' # declare fields first, then serialize
end

c = Charge.from_json('{"amountCents": 500}')
c.amount    # => 500
c.valid?    # => true
c.to_json   # => '{"amountCents":500,"note":null}'
```

Everything round-trips except `:value` (no type info to restore). JSON is handled with
Oj.

### A complete example — nesting, arrays, coercion

<!-- doctest -->
```ruby
class LineItem < FieldStruct::Base
  required :sku, :string
  required :qty, :integer
end

class Order < FieldStruct::Base
  required :id,    :string
  required :items, :array, of: LineItem
end

order = Order.from_json('{"id":"A1","items":[{"sku":"X","qty":"2"}]}')
order.id              # => "A1"
order.items.first.qty # => 2   (coerced from "2")
order.valid?          # => true
```

Nested structs and arrays-of-structs coerce and validate recursively — an `Order` with
an invalid `LineItem` is itself invalid.

### Introspecting a model

`Klass.metadata.to_h` is a copy-pasteable view of a model's shape — handy for *seeing*
a class without opening its source.

<!-- doctest -->
```ruby
class Widget < FieldStruct::Base
  required :name, :string
  optional :size, :integer
end

Widget.metadata.to_h[:name][:type]     # => "String"
Widget.metadata.to_h[:size][:required] # => false
```

### When things are invalid — errors

A FieldStruct always constructs; check `valid?` and read `errors`.

<!-- doctest -->
```ruby
class Account < FieldStruct::Base
  required :email, :string
end

a = Account.new(email: '   ')  # whitespace-only counts as missing
a.valid?         # => false
a.errors[:email] # => ["is required"]
```

What the messages mean and what to do:

| You see | It means | Do |
|---|---|---|
| `errors[:x] == ["is required"]` | required field is missing/blank (for `:string`, blank = nil/empty/whitespace) | provide a value, or make it `optional` |
| `["is invalid"]` | present but fails `format:`/`enum:`/`in:`, or a nested struct/array element is invalid | check the value against the constraint |
| `["could not be coerced: …"]` | coercion raised; under the default `:keep_raw` the raw value is kept | fix the input or change the field's type |
| `FieldStruct::UnknownAttributeError` | input had an undeclared key and the class set `unknown_attributes :raise` | declare the field, or drop the key |
| `FieldStruct::CoercionError` | coercion failed and the field/class uses `coercion_policy :raise` | fix the input or relax the policy |

### Common mistakes

1. **Setters are permissive — don't "fix" them.** `user.age = "30"` is *valid*; the
   type coerces. Readers are typed; writers accept anything coercible.
2. **`required` does not guarantee non-nil at runtime.** A constructed-but-invalid
   instance (or a `:replace` coercion failure) can hold `nil`. Gate on `valid?`.
3. **Whitespace-only strings are "missing"** for `:string` and its subtypes
   (`:uuid`/`:url`/`:email`/`:immutable_string`). `:binary` is the exception.
4. **`:array` needs `of:`; `:union` needs `of: [...]`** with ≥2 members (else
   `ArgumentError` at class-definition time).
5. **Option scoping** (misuse raises at declaration): `format:` → string-shaped +
   date/time/datetime; `enum:` → string/symbol; `in:` → numeric/temporal; `round:` →
   float/decimal; `values:` → boolean.

### Testing your models

Models are plain objects — test them directly:

```ruby
RSpec.describe Order do
  it 'coerces and validates a payload' do
    order = described_class.from_json(fixture('order.json'))
    expect(order).to be_valid
    expect(order.items.first.qty).to eq(2)
  end
end
```

### Agent toolbox

If you're an AI assistant working in this repo, reach for the gem's machine
affordances instead of guessing:

- `pp Klass.metadata.to_h` — *see* a model's fields/types without reading its source.
- `FieldStruct::Scaffold.from_json(json)` — bootstrap a model from a sample payload.
- `FieldStruct::RBS.generate(Klass)` — emit RBS for a model's accessors (Steep/Solargraph).
- The gem ships [`USAGE.md`](../USAGE.md) (full reference) and a Claude Code skill
  (`skills/field-struct/SKILL.md`) — both are in `bundle show field_struct`.

---

## Part 2 — Rails

### Where FieldStruct fits (and doesn't)

Use it for **API/webhook payloads**, service-object inputs/outputs, typed config, and
value objects. It is **not** a form object and **not** an ActiveRecord model — it
doesn't persist or query. Its ActiveModel-shaped surface (`valid?`, `errors`,
`model_name`, `to_model`) means error rendering and `*_path` helpers work, but treat it
as a typed value object, not a form backer.

### File placement (Zeitwerk)

Put your structs in an autoloaded path so Rails loads them by name. A common choice is
`app/structs/`:

```
app/structs/
  payments/
    webhook_payload.rb   # class Payments::WebhookPayload < FieldStruct::Base
    line_item.rb         # class Payments::LineItem < FieldStruct::Base
```

The path mirrors the constant: `app/structs/payments/line_item.rb` ↔
`Payments::LineItem`. Zeitwerk autoloads them — no `require` needed in app code. (If you
reference structs at boot, rely on eager loading in production.)

### Inbound — parsing a webhook or API request

```ruby
class WebhooksController < ApplicationController
  def nmi
    payload = Payments::WebhookPayload.from_json(request.raw_post)

    if payload.valid?
      ProcessTransaction.call(payload)
      head :ok
    else
      Rails.logger.warn(payload.errors.to_h)
      head :unprocessable_entity
    end
  end
end
```

`from_json` applies any `serialize :json` mapping, so a `firstName` JSON key lands in a
`first_name` field. Build the struct, check `valid?`, branch.

### Outbound — rendering JSON

```ruby
def show
  charge = build_charge
  render json: charge        # uses as_json/to_json, applying the :json mapping
end
```

### Scaffolding a model for a new integration

The fastest way to onboard a new provider:

1. Capture a sample payload (or several) into `spec/fixtures/` (or a console).
2. Generate a starter class and drop it into `app/structs/`:

   ```ruby
   # rails runner / console
   src = FieldStruct::Scaffold.from_json(File.read('spec/fixtures/nmi_sale.json'),
                                         class_name: 'Payments::NmiSale')
   File.write('app/structs/payments/nmi_sale.rb', src)
   ```

3. Refine: flip the `# enum?` hints into `enum:`, set the real `required` fields, add
   `description:`, and replace numeric-string `:string`s with `:integer`/`:big_decimal`
   where they're truly numeric (leave IDs and codes as `:string`).
4. Add a spec that loads the fixture and asserts `valid?`.

Feed `Scaffold.from_json` an **array** of captured payloads for sharper
required/optional and enum inference.

### Types for Steep / Solargraph (RBS)

If your app runs a type checker, generate RBS for your structs' accessors (the dynamic
`field` methods Sord can't see):

```ruby
# lib/tasks/field_struct_rbs.rake
namespace :field_struct do
  task rbs: :environment do
    classes = [Payments::WebhookPayload, Payments::LineItem]
    File.write('sig/field_structs.rbs',
               classes.map { |k| FieldStruct::RBS.generate(k) }.join("\n"))
  end
end
```

Generate RBS for nested/element classes too, so references like `::Payments::LineItem`
resolve.

---

## Where to go next

- [`USAGE.md`](../USAGE.md) — every type, option, and macro on one page.
- [`README.md`](../README.md) — the feature tour.
- `skills/field-struct/SKILL.md` — the bundled Claude Code skill.
