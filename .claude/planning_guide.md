# Planning Guide

> How to plan and build features in FieldStruct. Follow this before writing code.

---

## Planning Workflow

```
UNDERSTAND ──► VALIDATE ──► DESIGN ──► IMPLEMENT
     │              │           │           │
  What problem?   In scope?   Components   TDD
  Which slice?    Phase 1?    Tests        Red→Green→Refactor
  Success =?      Decided?    Risks
```

For FieldStruct, "in scope" and "decided" both resolve against `docs/origin/plan.md`. Most Phase 1 work has already been scoped into the 15-slice plan.

---

## User Story Format

```markdown
## User Story
**As a** [persona],
**I want to** [action],
**So that** [benefit].

## Acceptance Criteria
Given [context],
When [action],
Then [expected result].

## Out of Scope
- [What this does NOT do]

## Technical Notes
- [Patterns to follow, implementation hints]
```

### Example

```markdown
**As a** developer using FieldStruct,
**I want to** declare an array-of-strings field with `optional :tags, :array, of: :string`,
**So that** I get per-element coercion and presence checking without writing it myself.

**Given** I declare `optional :tags, :array, of: :string`,
**When** I pass `Klass.new(tags: ["a", 1, nil])`,
**Then** each element is coerced through the string type (yielding `["a", "1", ""]` or similar per type rules),
**And** `required` instead of `optional` would mark `[]` as missing.

**Out of Scope**: Arrays of FieldStruct subclasses (Phase 2 with nested FS).

**Technical Notes**: See Slice 7 in `docs/origin/plan.md`. `of:` resolves through the same registry-chain logic as the parent field type.
```

---

## Pre-Build Checklist

### Scope

- [ ] Falls within Phase 1 scope per `docs/origin/plan.md` (the in/out lists are authoritative)
- [ ] Aligns with the design invariants in `.claude/project_intent.md`
- [ ] If the work doesn't map to an existing slice, surface it before starting — the slice list is not arbitrary

### Design

- [ ] Locked decisions (D1–D15 in `plan.md`) are not contradicted
- [ ] If a configurable behavior is needed, use the class-macro pattern (see existing examples: `coercion_policy`, `immutable!`, `unknown_attributes`)
- [ ] Public API additions match the ActiveModel-shaped surface where applicable; we mirror shape, not code

### Technical

- [ ] Existing pattern to follow? (look at sibling type classes, the registry, etc.)
- [ ] Tests identified?
- [ ] `require_relative` wired into `lib/field_struct.rb`?
- [ ] If adding a Type, does it expose `coerce`, `missing?`, and `ruby_type`?

### Risk

- [ ] What could go wrong?
- [ ] Performance impact? (FieldStruct is a hot-path library — be conscious of allocations and method dispatch)
- [ ] Reversible? (Phase 1 is pre-1.0 — breaking changes are cheap, but still document them)

---

## Anti-Patterns

| Pattern | Bad | Good |
|---------|-----|------|
| Feature factory | Build because requested | Validate against `plan.md` first |
| Gold plating | Add extras "while here" | Build exactly what's in the slice |
| Premature abstraction | Generic framework for one use | Concrete code, extract when a second use appears |
| Big bang | Work in isolation, deliver all at once | Incremental slices |
| Test-after | Code first, tests later | TDD: failing test first |
| Over-engineering | Build for hypothetical future | Build for current slice |
| Under-specifying | "Implement types" | Specific slice from `plan.md` |
| Relitigating | Re-debate a locked decision mid-implementation | Surface it explicitly, get a new lock |

---

## Definition of Done

### Code

- [ ] Follows existing patterns (look at sibling files)
- [ ] Uses correct terminology (see glossary in `project_intent.md`)
- [ ] No Rubocop violations (`bundle exec rubocop`)
- [ ] YARD comments on public methods
- [ ] `require_relative` added to `lib/field_struct.rb` if a new file was created

### Testing

- [ ] TDD approach (failing test written first)
- [ ] Behavior-focused tests (see `tdd_guidelines.md`)
- [ ] Happy path + error cases
- [ ] All tests pass (`bin/rspec`)
- [ ] Coverage hasn't regressed (`COVERAGE=1 bin/rspec`)

### Commits

- [ ] Atomic commits (one logical change each)
- [ ] Conventional commit format (`feat:` / `fix:` / `refactor:`)
- [ ] Tests included with the code they prove
- [ ] Tests pass at every commit
- [ ] Commit messages explain *why*, not *what*

### Documentation

- [ ] README updated if public API changed
- [ ] CHANGELOG updated if a release-worthy change

---

## Incremental Delivery

The Phase 1 work is already broken into 15 slices in `docs/origin/plan.md`. Each slice follows the TDD commit rhythm (see `tdd_guidelines.md`). A slice's commit history reads like a changelog of the feature being built.

**Example: Slice 7 (Array type)**

| Step | TDD Cycle | Commit |
|------|-----------|--------|
| 1 | Failing spec: array field declares with `of:` and coerces elements | (in progress) |
| 2 | Implement `Types::Array#coerce`, wire `of:` resolution in DSL | `feat: add array type with element coercion` |
| 3 | (optional) Tidy resolution helper into `Field` or `Metadata` | `refactor: extract of: resolution into Field` |

Each step is independently valuable, testable, and produces an atomic commit.

---

## When to Ask for Clarification

Ask (don't assume) when:

- Requirements are ambiguous
- Multiple valid approaches exist *and the plan doesn't pick one*
- Scope is unclear
- Edge cases aren't covered in the plan
- A locked decision (D1–D15) seems to conflict with what you're being asked to do

### How to Ask

```markdown
**Question:** For `Types::Boolean#missing?`, should we:
A) Treat only `nil` as missing (current plan D4)
B) Also treat `false` as missing

**Recommendation:** A — matches what we locked in D4 (`false` is a valid value).
Flagging because the user said "I want falsey values to count" — wanted to
double-check that's intentional vs a misunderstanding of D4.
```
