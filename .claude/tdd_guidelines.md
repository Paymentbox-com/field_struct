# TDD Guidelines

> TDD is non-negotiable. Every change starts with a failing test.

---

## The TDD Cycle

```
RED ──────► GREEN ──────► REFACTOR ──┐
 │           │              │        │
 Write       Make test      Clean    │
 failing     pass           up       │
 test        (minimum)      code     │
 │                                   │
 └───────────────────────────────────┘
```

1. **RED**: Write test describing desired behavior. Run it — must fail.
2. **GREEN**: Write minimum code to pass. No optimization.
3. **REFACTOR**: Improve structure. Tests = safety net.

---

## Commit Rhythm

Each TDD cycle maps to atomic commits. The commit history tells the story of *why* code changed.

```
RED ─────────────► GREEN ──────────────► REFACTOR ────────────┐
 │                  │                      │                   │
 Write failing      Make it pass           Clean up            │
 test               (minimum code)         (no behavior change)│
 │                  │                      │                   │
 ┊                  git commit             git commit          │
 ┊                  "feat: ..."            "refactor: ..."     │
 ┊                  (includes the test)    (optional)          │
 │                                                             │
 └─────────────────────────────────────────────────────────────┘
```

### The Rule: Tests Ship With Their Code

The **green** commit includes both the test and the implementation. The test *proves* the code works — they are one logical change. Do not commit tests separately from the code that makes them pass.

### Commit Types by TDD Phase

| Phase | Commit type | Example | What's in the commit |
|-------|-------------|---------|---------------------|
| GREEN (new feature) | `feat:` | `feat: add array type with element coercion` | Test + implementation |
| GREEN (bug fix) | `fix:` | `fix: handle nil values in coercion_policy :replace` | Regression test + fix |
| REFACTOR | `refactor:` | `refactor: route initialize through assign_attributes` | Code restructuring only, no new behavior, same test count |
| Test-only (rare) | `test:` | `test: add coverage for registry parent fallback` | Tests for existing untested code |

### Feature Slice Rhythm

A slice is built as a sequence of small TDD cycles, each producing an atomic commit. The 15-slice plan in `docs/origin/plan.md` defines the slices.

```
Slice 7: "Array type with element coercion"

  Cycle 1 → feat: add array type with element coercion
             (test: declare :array field, coerce mixed input + impl)

  Cycle 2 → refactor: extract of: resolution into Field   (optional)
             (no new behavior — tests unchanged)
```

Each commit is independently revertable. Tests pass at every commit. The history reads like a changelog.

### Bug Fix Rhythm

Bug fixes follow the same pattern but start with reproducing the bug:

```
  Cycle 1 → fix: handle nil values in coercion_policy :replace
             (test: nil input keeps nil, no spurious error + fix)
```

The regression test and fix are a single commit — the test proves the fix works.

### When to Use `test:` Commits

The `test:` type is for adding tests to **existing untested code** — not for the normal TDD cycle. If you're writing a test as part of red/green, the test goes in the `feat:` or `fix:` commit.

```
# Normal TDD — test is part of the feat commit
feat: add immutable! macro

# Adding coverage to old code — standalone test commit
test: add missing specs for registry parent fallback edge cases
```

### Atomic Commit Principles

1. **One logical change per commit** — don't mix features, don't mix refactoring with behavior changes
2. **Tests pass at every commit** — never commit a broken state
3. **Independently revertable** — reverting any commit leaves the codebase in a working state
4. **Commit message explains why** — the diff shows *what* changed; the message explains *why*

---

## Test Behavior, Not Implementation

### DO: Test Outcomes

```ruby
it 'coerces string input to integer' do
  type = FieldStruct::Types::Integer.new
  expect(type.coerce("42")).to eq(42)
end

it 'marks empty string as missing' do
  type = FieldStruct::Types::String.new
  expect(type.missing?("")).to be true
end

it 'records error when value cannot be coerced' do
  klass = Class.new(FieldStruct::Base) do
    field :age, :integer
  end
  instance = klass.new(age: "abc")
  expect(instance.errors[:age]).to include(/coerce/)
end
```

### DON'T: Test Internals

```ruby
# BAD: Testing method calls
expect(type).to receive(:parse_value)

# BAD: Testing private methods
type.send(:normalize, "abc")

# BAD: Testing instance variables
instance.instance_variable_get(:@coerced_values)
```

### The Refactoring Test

> If you can refactor implementation without changing tests, your tests are correct. If refactoring breaks tests, they're testing implementation.

---

## Anti-Patterns

| Anti-Pattern | Bad | Good |
|--------------|-----|------|
| Method-centric structure | `describe '#coerce'` | `describe 'coercing a string value'` |
| Testing implementation | `expect(type).to receive(:parse)` | Test the parsing outcome |
| Testing internal state | `instance_variable_get(:@registry)` | `expect(klass.field_types.lookup(:string)).to eq(...)` |
| Mocking internals | `expect(FieldStruct::Types::String).to receive(:new)` | Use the real type |
| Testing framework | `expect(field.valid?).to be false` | Test the observable error |
| Brittle strings | `have_content('exact error message')` | Test for the error key/code |
| God tests | 20 assertions in one test | One behavior per test |
| Too many mocks | Everything doubled | Use real objects |

---

## Correct Patterns

### Describe Behaviors, Not Methods

**Don't** organize tests around method names — this couples tests to code structure:

```ruby
# BAD: Method-centric (brittle)
RSpec.describe FieldStruct::Types::Integer do
  describe '#coerce' do           # ← Coupled to method name
    it 'coerces strings' do
```

**Do** organize around capabilities and behaviors:

```ruby
# GOOD: Behavior-centric (durable)
RSpec.describe FieldStruct::Types::Integer do
  describe 'coercing string input' do  # ← Describes what the system does
    it 'returns the integer value' do
```

The behavior-focused version survives refactoring. Rename `coerce` → `cast`? Extract to `IntegerCoercer`? Tests don't break because they describe *what happens*, not *which method to call*.

### Test Outcomes

```ruby
RSpec.describe FieldStruct::Registry do
  describe 'looking up a registered type' do
    it 'returns the registered class' do
      registry = described_class.new
      registry.register(:string, FieldStruct::Types::String)
      expect(registry.lookup(:string)).to eq(FieldStruct::Types::String)
    end
  end
end
```

### Test State Changes

```ruby
it 'clears the field error after a good assignment' do
  klass = Class.new(FieldStruct::Base) { required :name, :string }
  instance = klass.new(name: "")
  expect(instance.errors[:name]).not_to be_empty

  instance.name = "Alice"
  expect(instance.errors[:name]).to be_empty
end
```

### Test Error Cases

```ruby
context 'with an unknown type name' do
  it 'raises an error from lookup' do
    registry = FieldStruct::Registry.new
    expect { registry.lookup(:nope) }.to raise_error(KeyError)
  end
end

context 'with coercion_policy :raise' do
  it 'raises CoercionError from the setter' do
    klass = Class.new(FieldStruct::Base) do
      coercion_policy :raise
      field :age, :integer
    end
    expect { klass.new(age: "abc") }.to raise_error(FieldStruct::CoercionError)
  end
end
```

### Context Organization

Organize by **scenarios and conditions**, not method signatures:

```ruby
RSpec.describe FieldStruct::Types::Array do
  describe 'coercing input' do
    context 'with valid element values' do
      it 'returns an array of coerced elements' do ... end
    end

    context 'with mixed valid and invalid elements' do
      context 'and class policy :keep_raw' do
        it 'preserves raw elements and records errors' do ... end
      end

      context 'and class policy :replace' do
        it 'replaces invalid elements with nil' do ... end
      end
    end
  end

  describe 'reporting missing values' do
    context 'when the value is nil' do
      it 'is missing' do ... end
    end

    context 'when the value is an empty array' do
      it 'is missing' do ... end
    end
  end
end
```

### Naming Guidance

| Level | Focus | Examples |
|-------|-------|----------|
| `describe` | Capability/behavior | `'coercing a string value'`, `'looking up a registered type'` |
| `context` | Scenario/condition | `'with valid input'`, `'when value is nil'`, `'with policy :raise'` |
| `it` | Expected outcome | `'returns the integer value'`, `'records an error'` |

---

## Bug Fix Workflow

**Every bug fix MUST start with a failing test that reproduces the bug.**

```
REPRODUCE ──► VERIFY ──► FIX ──► VERIFY
    │          fails      │      passes
    │                     │
    Write test         Write code
    for bug            to fix
```

### Example

```ruby
# Step 1: Write failing test
it 'preserves nil on :replace policy without spurious coercion error' do
  klass = Class.new(FieldStruct::Base) do
    coercion_policy :replace
    optional :age, :integer
  end
  instance = klass.new(age: nil)
  expect(instance.age).to be_nil
  expect(instance.errors[:age]).to be_empty
end

# Step 2: Run test — must fail
# Step 3: Fix the code (e.g. skip coercion on nil)
# Step 4: Run test — now passes
```

---

## Test Organization

Standard gem layout:

```
spec/
├── spec_helper.rb
├── field_struct_spec.rb               # top-level (e.g. VERSION)
├── field_struct/
│   ├── base_spec.rb
│   ├── registry_spec.rb
│   ├── metadata_spec.rb
│   ├── field_spec.rb
│   ├── errors_spec.rb
│   └── types/
│       ├── base_spec.rb
│       ├── string_spec.rb
│       ├── integer_spec.rb
│       ├── ...
│       └── array_spec.rb
└── support/                           # shared examples, helpers
```

Type specs test the type class directly (`Types::String.new.coerce(...)`). DSL-level specs (`Base#field`, macros, etc.) build small anonymous classes inline:

```ruby
let(:klass) do
  Class.new(FieldStruct::Base) do
    required :name, :string
    optional :age, :integer
  end
end
```

This keeps each spec self-contained — no shared test data leaking between specs.

---

## Running Tests

```bash
bin/rspec                           # All specs
bin/rspec spec/path/file_spec.rb    # Specific file
bin/rspec spec/path/file_spec.rb:42 # Specific line
COVERAGE=1 bin/rspec                # With coverage
bundle exec rake                    # Full suite + Rubocop
```

---

## Checklist

### Before Writing Code

- [ ] Slice identified in `docs/origin/plan.md`
- [ ] Acceptance criteria clear
- [ ] Test describes behavior, not implementation

### Red Phase

- [ ] Test written and fails
- [ ] Failure message makes sense

### Green Phase

- [ ] Minimum code to pass
- [ ] Test passes
- [ ] `require_relative` added if a new file was created

### Refactor Phase

- [ ] Code clean and readable
- [ ] Tests still pass
- [ ] No behavior change

### Before Commit

- [ ] All tests pass
- [ ] No skipped or pending tests (delete or fix them)
- [ ] Rubocop clean
- [ ] Commit is atomic (one logical change)
- [ ] Commit type matches the TDD phase (`feat:` / `fix:` / `refactor:` / `test:`)
- [ ] Tests are included with the code they prove (not in separate commits)

---

## Practical Patterns

### Anonymous Subclasses for DSL Specs

When testing DSL behavior, use `Class.new(FieldStruct::Base) { ... }` rather than named classes. Each spec gets its own throwaway class — no constant pollution, no spec-order dependencies.

```ruby
RSpec.describe FieldStruct::Base do
  describe 'declaring a required field' do
    let(:klass) do
      Class.new(described_class) do
        required :name, :string
      end
    end

    it 'reports errors for missing required value' do
      instance = klass.new
      expect(instance.errors[:name]).to include(/required/)
    end
  end
end
```

### Implementation Anti-Patterns to Avoid

These patterns test implementation details and create brittle tests:

```ruby
# BAD: Testing internal state
expect(registry.instance_variable_get(:@types)).to include(:string)

# BAD: Testing private methods
expect(field.send(:resolve_type, :integer)).to eq(...)

# BAD: Testing that a method was called
expect(klass).to have_received(:inherited)

# BAD: Copying implementation logic into the test
expected = "abc".upcase.strip
expect(type.coerce("abc")).to eq(expected)

# BAD: Testing class metadata
expect(FieldStruct::Base.field_types).to be_a(FieldStruct::Registry)
```

Instead, test observable outcomes through the public interface:

```ruby
# GOOD: Test the public interface
it 'inherits parent metadata when subclassed' do
  parent = Class.new(FieldStruct::Base) { required :name, :string }
  child = Class.new(parent) { optional :age, :integer }

  expect(child.new(name: "Alice").attribute_names).to eq([:name, :age])
end

# GOOD: Test error behavior
it 'raises when type name is not registered' do
  expect {
    Class.new(FieldStruct::Base) { field :foo, :unknown_type }
  }.to raise_error(KeyError)
end
```

### The Refactoring Litmus Test

> If you can refactor the implementation without changing tests, your tests are correct.
> If refactoring breaks tests, they're testing implementation details.

When you find yourself wanting to test a private method or internal state, ask:

1. What observable behavior does this enable?
2. Can I test that behavior through the public interface?
3. If not, should this logic be extracted to its own tested class?

### No Pending Specs

Pending specs are cruft. Either fix the underlying issue or delete the spec.

```ruby
# BAD: Will be ignored forever
it 'does something', pending: 'needs investigation' do
  ...
end

# GOOD: Delete and track the issue separately
# If there's a real bug, file an issue. Don't leave pending specs.
```
