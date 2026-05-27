# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Context Documents

Before starting any work, read these in order:

| Document | Purpose |
|----------|---------|
| `docs/origin/plan.md` | **Source of truth.** Phase 1 design decisions, slice plan, Phase 2+ backlog. |
| `.claude/project_intent.md` | What FieldStruct is/isn't, terminology, design invariants |
| `.claude/tdd_guidelines.md` | Test-driven development patterns (non-negotiable) |
| `.claude/planning_guide.md` | How to plan and build features |
| `docs/origin/first_discussion.md` | Original idea document — historical context |

---

## Project Overview

**FieldStruct** is a Ruby library for building POROs ("Plain Old Ruby Objects") with declared attributes that have enforced types, presence checks, and validation. The class collects its field declarations into a class-level `Metadata` object that is inspectable and introspectable. Each field is backed by a `Type` class that coerces values and decides what counts as "missing." Types live in a `Registry` that namespaces can extend or replace.

It is *not* a database layer, form object, or ActiveModel replacement. It mirrors ActiveModel's *interface shape* in places but reuses none of its code.

The library is in **Phase 1** (v0.1.0 in flight). The 15-slice plan lives in `docs/origin/plan.md`.

---

## Code Conventions

### JSON Handling

Use **Oj**, not the Ruby built-ins:

```ruby
Oj.load(json_string)   # not JSON.parse
Oj.dump(object)        # not object.to_json (the built-in)
```

### File loading

Standard `lib/field_struct.rb` entry point with explicit `require_relative` for every file. **No autoload, no Zeitwerk.** When adding a new file under `lib/field_struct/`, add a corresponding `require_relative` to `lib/field_struct.rb`.

### Documentation

Public methods are documented with YARD comments. Keep them tight — purpose, params, return, and any non-obvious behavior. Don't restate what the code already shows.

### Linting

Rubocop must pass before commit. Coverage is tracked via SimpleCov (`COVERAGE=1 bin/rspec`).

---

## Testing

**TDD is non-negotiable.** Every change starts with a failing test. See `.claude/tdd_guidelines.md` for the full discipline.

```bash
bin/rspec                           # Run all specs
bin/rspec spec/path/file_spec.rb    # Run specific file
bin/rspec spec/path/file_spec.rb:42 # Run specific line
bundle exec rake                    # Full suite + linters
COVERAGE=1 bin/rspec                # With coverage

# Sig / docs / release prep
bundle exec rake sigs:generate      # Regenerate sig/field_struct.rbs from YARD
bundle exec rake sigs:check         # Fail if committed sigs are stale (CI guard)
bundle exec rake sigs:validate      # rbs validate the committed sig file
bundle exec rake docs:generate      # YARD HTML to doc/  (--fail-on-warning)
bundle exec rake docs:stats         # List undocumented public methods
bundle exec rake release:check      # Full pre-flight (spec + rubocop + sigs + docs)
```

**Run `rake release:check` before every release commit.** It bundles specs, rubocop, the sigs staleness/validity guards, and a strict YARD build — broken doc links fail the build.

---

## Git Workflow

### Conventional Commits

```
type: description

# Examples for FieldStruct
feat: add array type with element coercion
fix: handle nil values in coercion_policy :replace
refactor: route initialize through assign_attributes
test: add missing specs for registry parent fallback
docs: add usage examples to README
chore: fill gemspec metadata
```

| Type | When to use |
|------|-------------|
| `feat` | New behavior (TDD green phase — includes tests + implementation) |
| `fix` | Bug fix (includes regression test + fix) |
| `refactor` | Code restructuring with no behavior change (tests unchanged) |
| `test` | Adding tests to existing untested code (not normal TDD) |
| `docs` | Documentation only |
| `chore` | Dependencies, CI, tooling, releases — no production code |

### Atomic Commits

Every commit is **one logical change** that passes all tests:

1. **Tests ship with their code** — the test that proves a feature works belongs in the same `feat:` commit, not a separate `test:` commit
2. **Tests pass at every commit** — never commit a broken state
3. **Independently revertable** — reverting any commit leaves the codebase working
4. **Message explains why** — the diff shows what; the message explains why

### Commit Rhythm (TDD)

- **GREEN** → `feat:` or `fix:` commit (test + implementation together)
- **REFACTOR** → `refactor:` commit (optional, no behavior change)
- Repeat per slice (see `docs/origin/plan.md` for the slice plan)

### Commit Message Format

```
feat: add coercion_policy macro with keep_raw, replace, raise modes

Wire the three policies into the setter pipeline. Default is
:keep_raw so existing instances keep working; subclasses can
override via the class macro. Inherited along the class chain.
```

- **Subject**: imperative mood, lowercase, no period, under 72 chars
- **Body** (optional): explain *why*, not *what*. Wrap at 72 chars.
- **Footer**: `Co-Authored-By:` when pair programming or AI-assisted

### Branches

- `main` is the released branch. Tagged releases come from here.
- `develop` is the integration branch — day-to-day work merges back into it.
- Per-feature branches live off `develop`, merged back into `develop` when the feature is done.
- Release flow: `develop` → `main` via PR when cutting a version.

There is no `$BRANCH_PREFIX` convention for this gem. Use descriptive branch names off `develop`.

---

## Tool Constraints

### GitHub CLI (`gh`)

`gh` works normally in most environments. **Only** if you see a TLS certificate error (e.g. `OSStatus -26276`, `x509: certificate signed by unknown authority`) when calling `gh`, the cause is Claude Code's sandbox mode — its TLS interception isn't trusted by `gh`'s Go TLS stack.

If (and only if) that happens: re-run the command outside sandbox mode, or ask Adrian to run it manually and paste the output. Do not assume `gh` is unavailable by default.

---

## When in doubt

The slice plan in `docs/origin/plan.md` is the authoritative roadmap. The design decisions D1–D15 in that document are locked unless explicitly revisited. If a question isn't answered there, ask before guessing.
