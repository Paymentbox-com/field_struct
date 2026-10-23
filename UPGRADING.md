# Upgrading FieldStruct

<!-- upgrading-range: 0.10.0..0.14.0 -->

What changes when you move a project from **0.10.x to 0.11, 0.12 or 0.13**, how
to find the code each change touches, and how to fix it. Written to be followed
step by step by a person or an AI agent. [`CHANGELOG.md`](CHANGELOG.md) has the
full history; this page is only what a caller can see.

## TL;DR

1. **Who must act:** every project on field_struct 0.10.x. Most will change a few spec expectations and nothing else; Steep users also regenerate RBS.
2. **Bump** the tag in your Gemfile (`tag: 'v0.13.1'`). If you also use **actionable**: its gemspec from v1.6.0 on requires `field_struct >= 0.12` (v1.5.x needs `>= 0.11`), so bump field_struct first or Bundler will refuse to resolve.
3. **Run your suite**, then match each failure against the [symptom index](#symptom-index) and apply that entry's Fix. Run every **Find** in the sections between your old and new version, even if nothing failed: some changes (rounding, base 10, BigDecimal from JSON) change values without raising.
4. **Regenerate any RBS you produce** with `FieldStruct::RBS.generate`, and fix hand-written sigs that copied the old output ([0.12](#012--generated-rbs-changes-no-runtime-changes)).
5. **How long:** about 15–60 minutes for a typical app. The fixes are mostly renames, a `.to_h`, and updated message expectations.

Find patterns use [ripgrep](https://github.com/BurntSushi/ripgrep) (`rg`); the
ones with `-P` need ripgrep built with PCRE2 (`rg --pcre2-version`). Run them
from your project root. A pattern finds *candidates*; read each hit.

## Straight from 0.10 to 0.13

You don't have to stop at 0.11 and 0.12: bump straight to `v0.13.1`, then walk
the [0.11](#011--correctness-and-safer-input), [0.12](#012--generated-rbs-changes-no-runtime-changes)
and [0.13](#013--safer-input-and-log-safety) sections in that order, running every
Find. The [reserved field names](#reserved-field-names) pattern already includes
the names 0.13 added, so a hit there covers both versions. If the failures are
hard to attribute, [bisect by version](#if-something-else-breaks).

## Symptom index

| You see | Version | Entry |
|---|---|---|
| `ArgumentError: field :x is reserved: FieldStruct::Base relies on #x …` at class load | 0.11, 0.13 | [Reserved field names](#reserved-field-names), [`with` / `dup`](#with-and-dup-are-reserved-field-names) |
| `ArgumentError: X.new expects a Hash (or an object responding to #to_hash), got Array` | 0.11 | [Non-Hash input](#new-and-assign_attributes-refuse-non-hash-input) |
| `ArgumentError: base: option does not apply to String fields. It applies to: Integer.` | 0.11 | [`base:` is reserved](#base-is-a-reserved-option-name) |
| `ArgumentError: zone: / strict: / sensitive: / element: …` at class load | 0.13 | [Newly recognized options](#option-names-that-are-now-recognized) |
| `ArgumentError: rbs_type: must be a non-empty String …` | 0.12 | [`rbs_type:` is recognized](#rbs_type-is-now-a-recognized-option) |
| `"010"` reads as 10, `"0x1A"` is invalid on an `:integer` | 0.11 | [Integer base 10](#integer-strings-parse-in-base-10) |
| `"0x1A"` is invalid on a `:float` | 0.13 | [Float hex](#float-refuses-hex-strings) |
| `round: 0` gives `4.0` / `0.4e1`, not `4` | 0.11 | [`round: 0`](#round-0-keeps-the-fields-type) |
| `12.345` rounds to `12.35` despite banker's `BigDecimal.mode` | 0.11 | [Rounding mode](#decimal-rounding-ignores-bigdecimalmode) |
| `NaN` / `Infinity` now invalid; no more `FloatDomainError` | 0.11 | [Non-finite](#nan-and-infinity-are-refused) |
| `:value` field holds `BigDecimal`; `to_json` writes `"2.25"` | 0.11 | [JSON decimals](#from_json-reads-decimals-as-bigdecimal) |
| Bundler: `oj` can't resolve | 0.11 | [Oj floor](#oj-must-be--3112) |
| Message-matching spec fails: `invalid value for Integer()` gone | 0.11 | [Numeric messages](#numeric-messages-name-the-input-class) |
| Message-matching spec fails: `cannot coerce "…" to boolean`, `no union member could coerce`, `could not coerce "…" for` | 0.13 | [No value echo](#messages-never-echo-the-input-value) |
| Array error gains `element at index N:` | 0.13 | [Array element index](#array-errors-name-the-element-index) |
| Array error says `elements at index N, M …` | 0.14 | [Every index](#array-errors-name-every-bad-index) |
| Mutating a `dup` no longer changes the original's `valid?` | 0.11 | [`dup` errors](#dup-and-clone-own-their-errors) |
| `RangeError` / `FloatDomainError` no longer raised by `.new` | 0.11 | [RangeError](#rangeerror-is-a-coercion-failure) |
| Steep: new errors on setters, array elements, unions | 0.12 | [0.12 section](#012--generated-rbs-changes-no-runtime-changes) |
| Bundler adds `tzinfo` and `concurrent-ruby`, or can't resolve `tzinfo` | 0.14 | [tzinfo dependency](#new-runtime-dependency-tzinfo) |
| `zone: 'America/Denver'` no longer raises; refusal message reworded | 0.14 | [IANA names](#zone-accepts-iana-names) |

---

## 0.11 — correctness and safer input

### Integer strings parse in base 10
<!-- upgrading: integer-base-10 -->

- **Symptom:** an `:integer` field given `"010"` holds `10` (was `8`); `"0x1A"` /
  `"0b11"` stay raw with `could not be coerced: Integer fields expect a base-10
  integer, got a String that is not one` (were `26` / `3`).
- **Find:** integer fields, and spec literals with a leading `0` or radix prefix.
  The inputs themselves usually arrive at runtime — no pattern finds those.
  ```sh
  rg -nP --type ruby '(field|required|optional)\s+:\w+,\s*:integer\b'
  rg -nP "['\"]\s*[-+]?0([xXbBoO]|\d)" spec
  ```
- **Fix:** if the input really is hex (or another radix), say so.
  ```ruby
  required :code, :integer             # before: "1A" was refused, "0x1A" read as 26
  ```
  <!-- doctest -->
  ```ruby
  class Payment < FieldStruct::Base
    required :code, :integer, base: 16 # after: "1A" reads as 26
  end
  Payment.new(code: '1A').code # => 26
  ```
- **Why:** `Kernel#Integer` honoured Ruby literal prefixes, so a zero-padded id became octal.

### `round: 0` keeps the field's type
<!-- upgrading: round-zero-keeps-type -->

- **Symptom:** `:decimal` / `:float` with `round: 0` holds `BigDecimal('4')` /
  `4.0` (was `4`). Specs comparing with `eq(4)` still pass (`4.0 == 4`), but
  `be_a(Integer)`, `.to_s` and JSON output change (`{"total":4.0}`; a `:decimal`
  writes `"4.0"`).
- **Find:**
  ```sh
  rg -n 'round:\s*0\b'
  ```
- **Fix:** convert where you need an Integer, or declare the field `:integer`.
  <!-- doctest -->
  ```ruby
  class Order < FieldStruct::Base
    optional :total, :float, round: 0
  end
  order = Order.new(total: 4.4)
  order.total.to_s     # => "4.0"
  order.total.to_i     # => 4
  ```
- **Why:** a field always holds its own type.

### `:decimal` rounding ignores `BigDecimal.mode`
<!-- upgrading: decimal-rounding-ignores-mode -->

- **Symptom:** a host that sets `BigDecimal.mode(BigDecimal::ROUND_MODE, :banker)`
  now gets `12.345` → `12.35` at `round: 2` (was `12.34`). Same for `:float`.
- **Find:**
  ```sh
  rg -n 'BigDecimal\.mode|ROUND_MODE'
  ```
- **Fix:** if you wanted banker's rounding on a field, drop `round:` and round
  before assigning (`value.round(2, half: :even)`), or wrap it in a custom type.
- **Why:** a global, process-wide setting changed stored money values.

### NaN and Infinity are refused
<!-- upgrading: non-finite-refused -->

- **Symptom:** `:float` / `:decimal` given `NaN` or `±Infinity` (Float, BigDecimal,
  String or JSON `1e400`) are now invalid —
  `could not be coerced: BigDecimal fields expect a finite number, got a non-finite String`.
  `:integer` used to raise `FloatDomainError` out of `.new` / `from_json`; it now
  records a coercion failure (or raises `FieldStruct::CoercionError` under
  `coercion_policy :raise`). A `:union` no longer stores `"NaN"` in a `:string` member.
- **Find:**
  ```sh
  rg -n 'NaN|Infinity|FloatDomainError'
  ```
- **Fix:** represent "unknown" as `nil`, and drop `rescue FloatDomainError` around
  construction — check `valid?` / `errors` instead.
- **Why:** a non-finite number is not a value any of these fields can hold.

### Numeric messages name the input class
<!-- upgrading: numeric-messages-name-class -->

- **Symptom:** a spec matching `invalid value for Integer(): "abc"` (or `Float()`,
  `BigDecimal()`) fails; the message is now
  `could not be coerced: Integer fields expect a base-10 integer, got a String that is not one`
  (`Float fields could not read a String as a number`, …).
- **Find:**
  ```sh
  rg -n 'invalid value for (Integer|Float|BigDecimal)'
  ```
- **Fix:** match the new text, or better, match the stable prefix.
  ```ruby
  expect(rec.errors[:n].first).to match(/invalid value for Integer\(\)/) # before
  expect(rec.errors[:n].first).to start_with('could not be coerced:')     # after
  ```
- **Why:** the old message echoed the raw input into logs.

### `new` and `assign_attributes` refuse non-Hash input
<!-- upgrading: non-hash-input-refused -->

- **Symptom:** `ArgumentError: Person.new expects a Hash (or an object responding to
  #to_hash), got Array`. Raised for an array of pairs (used to work), `new([])`
  (used to build an empty instance) and `new("x")` (was `NoMethodError`).
  `assign_attributes(nil)` raises the same `ArgumentError` (was `NoMethodError`);
  `new(nil)` now builds an empty instance. An *unpermitted*
  `ActionController::Parameters` raises Rails' `UnfilteredParameters`.
- **Find:** literal arrays and `nil` only; pairs built in a variable surface when
  the suite runs.
  ```sh
  rg -nP '\.(new|assign_attributes)\(\s*(\[|nil\b)'
  ```
- **Fix:**
  ```ruby
  Person.new([[:name, 'Ann']])   # before
  ```
  <!-- doctest -->
  ```ruby
  class Person < FieldStruct::Base
    optional :name, :string
  end
  pairs = [[:name, 'Ann']]
  Person.new(pairs.to_h).name # => "Ann"
  ```
  For Rails params, `permit` them first (`Person.new(params.require(:person).permit(:name))`).
- **Why:** non-Hash input was silently misread; ActiveModel requires a Hash too.

### Reserved field names
<!-- upgrading: reserved-field-names -->

- **Symptom:** at class load, `ArgumentError: field :errors is reserved:
  FieldStruct::Base relies on #errors, and a field would shadow it. Pick another
  name; serialize :json can keep the external key (e.g. serialize :json,
  errors_field: 'errors').` The full list is `FieldStruct::Base::RESERVED_FIELD_NAMES`
  (includes `errors attributes hash class send to_h inspect as_json raise
  initialize_copy`, and from 0.13 `with dup`). `method`, `name` and `type` stay legal.
- **Find:** (covers 0.11 and 0.13 names)
  ```sh
  rg -nP --type ruby '(field|required|optional)\s+:(errors|attributes|attribute_names|assign_attributes|as_json|to_json|to_h|to_model|model_name|inspect|hash|class|send|public_send|freeze|instance_variable_set|initialize|initialize_copy|raise|with|dup|deconstruct|deconstruct_keys|json_value|temporal_json_value|apply_defaults|run_cross_field_validators|validate_field|apply_coercion_policy|record_coercion_failure)\b'
  ```
- **Fix:** rename the field and keep the wire name with a `serialize :json` mapping.
  ```ruby
  class Reply < FieldStruct::Base
    optional :errors, :value          # before
  end
  ```
  <!-- doctest -->
  ```ruby
  class Reply < FieldStruct::Base
    optional :errors_field, :value    # after
    serialize :json, errors_field: 'errors'
  end
  Reply.from_json('{"errors":["late"]}').errors_field # => ["late"]
  Reply.new(errors_field: ['late']).to_json # => '{"errors":["late"]}'
  ```
  Update readers in calling code (`reply.errors` → `reply.errors_field`).
- **Why:** these fields broke equality, `inspect` and validation, or crashed the class body.

### `from_json` reads decimals as BigDecimal
<!-- upgrading: from-json-bigdecimal -->

- **Symptom:** after `from_json`, a `:value` field (or a number inside a `:value`
  Hash/Array) holds `BigDecimal` instead of `Float`, and `to_json` writes it as a
  string (`{"v":"2.25"}`, was `{"v":2.25}`). `:decimal` fields now get exact digits.
  JSON `1e400` into `:integer` is `10**400` (was `FloatDomainError`); an `:integer`
  refuses a decimal with more than 4300 integer digits.
- **Find:** `:value` fields, then the `from_json` paths that feed them.
  ```sh
  rg -nP --type ruby '(field|required|optional)\s+:\w+,\s*:value\b'
  rg -n 'from_json'
  ```
- **Fix:** give the number a type (`optional :rate, :float`), or convert where you
  read it (`rec.meta['rate'].to_f`). `:float` fields are unchanged.
- **Why:** parsing through a Float lost digits before a `:decimal` field ever saw them.

### Oj must be >= 3.11.2
<!-- upgrading: oj-floor -->

- **Symptom:** `bundle update field_struct` fails to resolve `oj`.
- **Find:**
  ```sh
  rg -nw oj Gemfile Gemfile.lock
  ```
- **Fix:** loosen the pin, e.g. `gem 'oj', '>= 3.11.2'`, then `bundle update oj field_struct`.
- **Why:** older Oj ignores `decimal_class:`, which the BigDecimal change depends on.

### `base:` is a reserved option name
<!-- upgrading: base-reserved-option -->

- **Symptom:** at class load, `ArgumentError: base: option does not apply to
  String fields. It applies to: Integer.` — for `base:` kept as metadata on a
  non-integer field, and for a custom type that reads `base:` without declaring it.
- **Find:**
  ```sh
  rg -nP --type ruby '(field|required|optional)\s+:\w+,\s*:(?!integer\b)\w+[^#\n]*\bbase:'
  rg -nP 'def coerce\(.*\bbase:'
  ```
- **Fix:** in a custom type, declare the option.
  ```ruby
  def self.own_option_schema = {base: option(type: [::Integer])}
  ```
  On a built-in type, rename the metadata key.
- **Why:** an option some registered type declares is FieldStruct's, and is checked like `round:`.

### `dup` and `clone` own their errors
<!-- upgrading: dup-own-errors -->

- **Symptom:** `b = a.dup; b.name = ''` no longer makes `a.valid?` false. Only code
  that relied on the shared `errors` (unlikely) notices.
- **Find:** no reliable pattern; candidates:
  ```sh
  rg -nP '\.(dup|clone)\b'
  ```
- **Fix:** validate the copy you changed. Copies are still shallow — mutate nested
  structs through `with` (0.13) or by re-assigning.
- **Why:** a copy that mutates its original's errors was a bug.

### RangeError is a coercion failure
<!-- upgrading: range-error-policy -->

- **Symptom:** `Complex(1, 2)` into `:integer` / `:float`, or a custom type raising
  `RangeError` / `FloatDomainError`, no longer raises out of `.new`; it follows the
  field's `coercion_policy`.
- **Find:**
  ```sh
  rg -nP 'rescue\s+.*\b(FloatDomainError|RangeError)\b'
  ```
- **Fix:** check `valid?` / `errors`, or set `coercion_policy :raise` and rescue
  `FieldStruct::CoercionError`.
- **Why:** every coercion failure goes through one policy.

---

## 0.12 — generated RBS changes, no runtime changes

Nothing here changes runtime behaviour except that `rbs_type:` is now a
recognized option. If you don't generate RBS or run Steep, only the
[`rbs_type:`](#rbs_type-is-now-a-recognized-option) entry can affect you. Otherwise:
regenerate, then fix what Steep reports.

**Find, for every entry below:** where you generate, and which sigs you keep.

```sh
rg -n 'FieldStruct::RBS\.generate'
rg -l 'FieldStruct::Base' sig
```

### Setters are typed
<!-- upgrading: rbs-typed-writers -->

- **Symptom:** after regenerating, Steep can report an argument type mismatch on
  `user.age = "30"`: writers are `(::Integer? value) -> ::Integer?` (were
  `(untyped value) -> untyped`). Runtime unchanged — the setter still coerces.
- **Find:** the generator call above, then `steep check`. No pattern finds loose assignments.
- **Fix:** assign the coerced type, or pass loose input through a Hash API, whose
  values stay `Object?`.
  ```ruby
  user.age = params[:age]                      # Steep error after 0.12
  user.assign_attributes(age: params[:age])    # fine: Hash[Symbol, Object?]
  ```
- **Why:** the sig now says what the reader will return.

### Generated output opens with a header comment
<!-- upgrading: rbs-header -->

- **Symptom:** a committed, generated `.rbs` differs from a fresh run (a staleness
  check fails) only by `# Generated by FieldStruct::RBS. Types describe a valid instance: …`.
- **Find:** the generator call above.
- **Fix:** regenerate and commit.
- **Why:** an invalid instance can hold other values; the header says so.

### Scalar array elements are nullable
<!-- upgrading: rbs-nullable-array-elements -->

- **Symptom:** Steep reports a possible `nil` on `rec.tags.first.upcase`:
  `of: :string` is now `::Array[::String?]` (was `::Array[::String]`). Arrays of
  nested structs stay non-nil.
- **Find:** hand-written sigs that copied the old shape.
  ```sh
  rg -n '::Array\[::[A-Z]\w*\]' sig
  ```
- **Fix:** handle the `nil` (`rec.tags.compact`, `&.`), or `rbs_type:` the field
  if your own rule guarantees no nils.
- **Why:** `["x", nil]` passes validation, so the old sig was false.

### Generic arguments are always present
<!-- upgrading: rbs-generic-arguments -->

- **Symptom:** a custom type whose `ruby_type` is `::Hash` / `::Array` / `::Range`
  now emits `::Hash[untyped, untyped]` (bare `::Hash` failed `rbs validate`).
- **Find:**
  ```sh
  rg -nU 'def ruby_type[\s=]*(::)?(Hash|Array|Range)\b'
  ```
- **Fix:** nothing required; to be precise, add the hook to the type.
  ```ruby
  def rbs_type = '::Hash[::Symbol, ::String]'
  ```
- **Why:** RBS rejects a generic class without its arguments.

### Unions render booleans as `bool`
<!-- upgrading: rbs-union-bool -->

- **Symptom:** `(::String | bool)` replaces `(::String | ::TrueClass | ::FalseClass)`;
  a union with a `:value` member collapses to `untyped`.
- **Find:**
  ```sh
  rg -n 'TrueClass \| ::FalseClass' sig
  ```
- **Fix:** regenerate; update hand-written sigs to `bool`.
- **Why:** shorter and what RBS means by a boolean.

### Optional `:value` fields are `untyped`
<!-- upgrading: rbs-optional-value-untyped -->

- **Symptom:** `untyped?` becomes `untyped` in generated output.
- **Find:**
  ```sh
  rg -n 'untyped\?' sig
  ```
- **Fix:** regenerate; `untyped` already admits `nil`.
- **Why:** `untyped?` is redundant.

### `rbs_type:` is now a recognized option
<!-- upgrading: rbs-type-option -->

- **Symptom:** a field that carried `rbs_type:` as free metadata now raises
  `ArgumentError: rbs_type: must be a non-empty String of RBS (e.g. rbs_type:
  '::ActiveRecord::Relation'), got …` if it isn't a non-blank String, and
  `rbs_type` disappears from `Field#options` (read it as `Field#rbs_type`).
- **Find:**
  ```sh
  rg -n 'rbs_type:'
  ```
- **Fix:** pass a String of RBS, or rename your metadata key.
- **Why:** FieldStruct now emits that type for the field.

### The gem's own signatures admit `nil`
<!-- upgrading: own-sigs-admit-nil -->

- **Symptom:** Steep only. `Base#attributes`, `#to_h`, `#as_json`,
  `#deconstruct_keys` return `::Hash[Symbol, Object?]`, `Field#options` and
  `Metadata#to_h` admit `nil` values, and `**options` are `**Object?`. Code that
  used those values as non-nil gets new Steep errors.
- **Find:** no reliable pattern; run `steep check`.
- **Fix:** handle the `nil`, as the runtime always required.
- **Why:** the old sigs claimed non-nil values the runtime does return as `nil`.

---

## 0.13 — safer input and log safety

### `with` and `dup` are reserved field names
<!-- upgrading: reserved-with-dup -->

- **Symptom:** at class load, `ArgumentError: field :with is reserved:
  FieldStruct::Base relies on #with, and a field would shadow it. …` (same for `:dup`).
- **Find:**
  ```sh
  rg -nP --type ruby '(field|required|optional)\s+:(with|dup)\b'
  ```
- **Fix:**
  ```ruby
  optional :with, :string           # before
  ```
  <!-- doctest -->
  ```ruby
  class Rule < FieldStruct::Base
    optional :with_field, :string   # after
    serialize :json, with_field: 'with'
  end
  Rule.from_json('{"with":"x"}').with_field # => "x"
  ```
- **Why:** `with` is now a `Base` method and relies on `dup`.

### Array errors name the element index
<!-- upgrading: array-element-index -->

- **Symptom:** an `:array` coercion error gains the element's 0-based index:
  `could not be coerced: element at index 1: Integer fields expect a base-10
  integer, got a String that is not one` (was without `element at index 1: `);
  same in `CoercionError` under `:raise`, which now says `could not coerce Array
  input for ids: …`. `describe` lines for arrays gain `— element accepts …`.
- **Find:** message and `describe` expectations; no pattern tells array fields apart.
  ```sh
  rg -n 'could not be coerced: ' spec
  rg -nP '(?<!RSpec)\.describe\b' spec
  ```
- **Fix:**
  ```ruby
  expect(rec.errors[:ids]).to eq(['could not be coerced: Integer fields expect …'])                     # before
  expect(rec.errors[:ids]).to eq(['could not be coerced: element at index 1: Integer fields expect …'])  # after
  ```
- **Why:** with dozens of elements, the failing one has to be named.

### Messages never echo the input value
<!-- upgrading: messages-never-echo-values -->

- **Symptom:** message-matching specs fail. New shapes:

  | Where | Before | After |
  |---|---|---|
  | `:boolean` | `cannot coerce "maybe" to boolean` | `Boolean fields expect true, false, 1, 0 or one of the strings "true", "1", "false", "0", got a String that is not one` (non-String: `…, got Hash`) |
  | `:union` | `no union member could coerce "abc"` | `no union member (Integer \| Boolean) could coerce String input` |
  | `coercion_policy :raise` | `could not coerce "abc" for cents: …` | `could not coerce String input for cents: …` |
  | `from_json` non-object root | `…, got Array: ["x"]` | `…, got Array` |
  | `from_json` invalid JSON | Oj's message, quoting the input | `from_json could not parse its input as JSON (unexpected character at line 1, column 7)` — still `EncodingError`, no longer with the Oj error as `cause` |
  | `:integer` / `:float` / `:decimal` | `cause` was Kernel's `invalid value for Integer(): "…"` | no `cause` |

- **Find:**
  ```sh
  rg -nP 'cannot coerce .* to boolean|no union member could coerce|could not coerce \S+ for|JSON object root, got \w+: |unexpected character|parse\.c'
  rg -n '\.cause\b'
  ```
  `unexpected character` also matches the new message; check those hits by eye.
- **Fix:** match on the field and class, not the value.
  ```ruby
  expect { rec }.to raise_error(FieldStruct::CoercionError, /could not coerce "abc" for cents/)    # before
  expect { rec }.to raise_error(FieldStruct::CoercionError, /could not coerce String input for cents/) # after
  ```
  If you need the raw value for debugging, read the field (`:keep_raw` keeps it).
- **Why:** payment data must not reach logs or error reporters.

### `:float` refuses hex strings
<!-- upgrading: float-refuses-hex -->

- **Symptom:** `"0x1A"` on a `:float` stays raw with `could not be coerced: Float
  fields expect a base-10 number, got a String that is not one` (was `26.0`).
  `"017"` is still `17.0`; `"1e3"`, `".5"`, `"1_000.5"` unchanged.
- **Find:**
  ```sh
  rg -nP --type ruby '(field|required|optional)\s+:\w+,\s*:float\b'
  rg -nP "['\"]\s*[-+]?0[xX]" spec
  ```
- **Fix:** convert hex before assigning (`Integer(str, 16).to_f`), or use an
  `:integer` field with `base: 16`.
- **Why:** `:integer` and `:float` both read base 10 now.

### Option names that are now recognized

`strict:`, `sensitive:`, `zone:` and `element:` (0.13) — like `base:` (0.11) and
`rbs_type:` (0.12) — used to pass through onto a field as free metadata. They are
now checked at declaration.

- **Symptom:** at class load, e.g. `ArgumentError: zone: option does not apply to
  String fields. It applies to: Time, DateTime.`, `sensitive: must be true or false,
  got String`, or `zone: on Time expects "UTC" or a UTC offset like "+00:00" or
  "-06:00", got "America/Denver"…`.
- **Find:**
  ```sh
  rg -nP --type ruby '(field|required|optional)\s+:\w+,[^#\n]*\b(strict|sensitive|zone|element|rbs_type|base):'
  ```
- **Fix:** rename your metadata key, or adopt the real option ([below](#new-opt-in--worth-adopting)).
- **Why:** a known option is validated so a typo can't silently do nothing.

## 0.13 → 0.14 (unreleased)

Not released yet; these entries describe `develop`. Fields that declare `"UTC"` or a
fixed offset behave exactly as in 0.13.

### New runtime dependency: tzinfo
<!-- upgrading: tzinfo-dependency -->

- **Symptom:** `bundle install` adds `tzinfo` (2.0.x) and `concurrent-ruby` to
  `Gemfile.lock` in an app that did not already have them (Rails apps do), so a
  frozen / deployment install refuses the stale lockfile. An app whose lock pins
  `tzinfo` 1.x (Rails 6.0 and older) can't resolve: `Bundler could not find
  compatible versions for gem "tzinfo"`.
- **Find:**
  ```sh
  rg -n '^\s+tzinfo \(' Gemfile.lock
  ```
  No hit: you gain it. A `1.` version: see Fix.
- **Fix:** `bundle update field_struct --conservative` and commit the lockfile.
  With tzinfo 1.x pinned by an older Rails, stay on 0.13 until Rails is on 6.1+.
  On a system without OS zoneinfo (Windows, slim containers) also add
  `gem 'tzinfo-data'` — needed only if you declare IANA names, and the declaration
  tells you so.
- **Why:** `zone: 'America/Denver'` needs a zone database and Ruby's stdlib has
  none. tzinfo is required lazily, only when a field declares a name, so a
  `"UTC"` / `"±HH:MM"` field never loads it.

### `zone:` accepts IANA names
<!-- upgrading: zone-accepts-iana-names -->

- **Symptom:** a spec expecting `ArgumentError` for `zone: 'America/Denver'` fails
  — it now declares fine. A spec matching the refusal message fails; it was
  `zone: on Time expects "UTC" or a UTC offset like "+00:00" or "-06:00", got "MST".
  Zone names such as "America/Denver" are not accepted: …` and is now
  `zone: on Time expects an IANA name like "America/Denver", "UTC" or a UTC offset
  like "-06:00", got "MST". Use an Area/Location name: …`.
- **Find:**
  ```sh
  rg -n 'expects "UTC" or a UTC offset|no time zone database' spec
  ```
- **Fix:**
  ```ruby
  expect { decl }.to raise_error(ArgumentError, /expects "UTC" or a UTC offset/)    # before
  expect { decl }.to raise_error(ArgumentError, /expects an IANA name like/)        # after
  ```
  If you declared a fixed offset because names were refused, consider the name:
  `zone: 'America/Denver'` follows DST where `'-06:00'` does not (see
  [USAGE](USAGE.md#zones-zone) for the gap and overlap rules).
- **Why:** a fixed offset is wrong for half the year in any DST zone.
Not released yet; these entries describe `develop`.

### Array errors name every bad index
<!-- upgrading: array-every-index -->

- **Symptom:** with more than one bad element, an `:array` error lists them all:
  `could not be coerced: elements at index 1, 4 (index 1 shown): Integer fields
  expect …` (was `element at index 1: …`), the same in `CoercionError` under
  `:raise`, and `elements at index 2, 3 are invalid` for `element:` validation
  (was `element at index 2 is invalid`). One bad element reads exactly as before.
- **Find:**
  ```sh
  rg -n 'element at index \d' spec
  ```
  Only hits whose input has two or more bad elements change.
- **Fix:**
  ```ruby
  expect(rec.errors[:ids]).to eq(['element at index 2 is invalid'])          # before
  expect(rec.errors[:ids]).to eq(['elements at index 2, 3 are invalid'])     # after
  ```
  Or match the stable part: `/\Aelements? at index /`.
- **Why:** fixing one element per resubmission is the failure mode this avoids.

### `describe` lists element options by name
<!-- upgrading: array-describe-names-only -->

- **Symptom:** an `:array` field's `describe` line ends `— element accepts in,
  base, strict` instead of `— element accepts in (Array | Range), base (Integer),
  strict (TrueClass | FalseClass)`.
- **Find:**
  ```sh
  rg -n 'element accepts \w+ \(' spec
  ```
- **Fix:** drop the shapes from the expectation; read them from the element type
  (`FieldStruct::Types::Integer.option_schema`) if you need them.
- **Why:** the shapes doubled every array line's length and belong to the element type.

---

## New, opt-in — worth adopting

None of these change defaults. Each is a one-line change per field.

| Option | Since | Use it when | Reference |
|---|---|---|---|
| `strict: true` | 0.13 | money and id fields where `12.7` must not become `12`, or a Hash must not become a String | [USAGE](USAGE.md#strict-coercion-strict-true) |
| `sensitive: true` | 0.13 | card data, tokens, PII — masks the value in `inspect` / `pp` / error suffixes | [USAGE](USAGE.md#log-safety-error-messages-and-sensitive-fields) |
| `zone: '-06:00'`, `zone: 'America/Denver'` | 0.13, 0.14 | zone-less timestamps that must mean the same instant on every server (a name follows DST) | [USAGE](USAGE.md#zones-zone) |
| `#with(**changes)` | 0.13 | "updating" an `immutable!` / frozen instance, or re-validating after a nested change | [USAGE](USAGE.md#copying-with-changes-with) |
| `element: {…}` | 0.13 | per-element options on an array (`of: :integer, element: {strict: true}`) | [USAGE](USAGE.md#element-options-element) |
| `unknown_attributes :raise` | — | every struct that reads payment or API input (nested classes don't inherit it) | [USAGE](USAGE.md#payment-and-api-boundaries-unknown_attributes-raise) |
| `rbs_type: '…'` | 0.12 | a `:value` or custom field whose real type FieldStruct can't derive | [USAGE](USAGE.md#rbs-for-your-own-classes) |
| `base: 16` | 0.11 | an integer that arrives as hex (or any radix 2..36) | [USAGE](USAGE.md#the-numeric-contract) |

## If something else breaks

To tell a FieldStruct change from a bug in your code:

1. **Read the message.** FieldStruct coercion errors start with `could not be
   coerced:` (field errors) or `could not coerce <Class> input for <field>:`
   (`CoercionError`), and declaration errors name the field or option. Anything
   else is probably yours.
2. **Bisect by version.** Pin the Gemfile to each release tag in turn and rerun the
   one failing spec:
   ```ruby
   gem 'field_struct', git: 'https://github.com/Paymentbox-com/field_struct', tag: 'v0.11.0'
   ```
   `bundle update field_struct --conservative && bundle exec rspec path/to/failing_spec.rb`.
   The first tag where it fails names the section above to read.
3. **Ask the model.** `puts Klass.describe` and `pp Klass.metadata.to_h` show what
   each field accepts in the installed version.
4. **Still unexplained?** Open an issue with the field declaration, the input's
   class (not the value, if it's sensitive), and the old and new behaviour.
