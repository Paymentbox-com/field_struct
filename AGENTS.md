# Working with the field_struct gem

This repo provides **FieldStruct** — a Ruby gem for typed POROs (declared fields with
coercion and validation). This file routes AI coding agents to the right docs and the
things most often gotten wrong. (For *contributing to the gem itself*, see
`CLAUDE.md`.)

## Read these

- **[`docs/getting_started.md`](docs/getting_started.md)** — how to use it in a repo
  (general Ruby + Rails): a task→API map, an error→fix table, and a worked example.
- **[`USAGE.md`](USAGE.md)** — dense reference: every type, option, and macro.
- **[`README.md`](README.md)** — feature overview.
- **[`UPGRADING.md`](UPGRADING.md)** — moving to a newer version: symptom, Find, fix.
- `skills/field-struct/SKILL.md` — the bundled Claude Code skill.

## The six gotchas

1. **Setters are permissive** — `user.age = "30"` is valid (the type coerces). Don't "fix" it.
2. **`required` ≠ non-nil at runtime** — an invalid instance can hold `nil`. Gate on `valid?`.
3. **Whitespace-only strings count as missing** for `:string` and its subtypes.
4. **`:array` needs `of:`; `:union` needs `of: [...]`** (≥2 members).
5. **Option scoping**: `format:`→string/date-ish, `enum:`→string/symbol, `in:`→numeric/temporal, `round:`→float/decimal, `base:`→integer, `strict:`→string-shaped/integer, `zone:`→time/datetime, `values:`→boolean, `element:`→array (a Hash of the element type's options); `sensitive:` works on any type. A misapplied known option raises at class load and names the types it applies to; an *unknown* option passes through onto the Field untouched (kept for downstream tooling). You don't have to memorize this table — ask the type (next section).
6. **`valid?` is computed on assignment, not on read.** Mutating a nested struct or an array element in place doesn't refresh the parent's errors. Assign the field again (or use `with`) to re-validate. See [USAGE](USAGE.md#validity-is-computed-on-assignment-shallow-valid-staleness).

## Upgrading

Moving a project to a newer field_struct? [`UPGRADING.md`](UPGRADING.md) lists every
visible change since 0.10 with a symptom, a Find command, and a fix. Procedure:

1. Read your old version from `Gemfile.lock` (`field_struct (x.y.z)`) and the target
   tag. Open `UPGRADING.md` (repo root, or `bundle show field_struct` after bumping)
   and read every section from the one after your old version to the target.
2. Bump the Gemfile tag. If the project uses **actionable** >= 1.6, field_struct
   must be >= 0.12 (its gemspec says so); if `oj` is pinned below 3.11.2, loosen it.
   `bundle update field_struct`.
3. Check `rg --pcre2-version` works in your shell. Run the Find of every entry
   the TL;DR lists as **silent**, from the project root, and read each hit using the
   entry's narrowing rule. Run the other entries' Finds only for code the suite
   doesn't reach; those changes raise or fail a spec.
4. Apply the matching **Fix** to each real hit. Don't change behaviour you weren't
   asked to — e.g. keep a renamed reserved field's wire name with `serialize :json`.
5. Run the full suite. Match each failure against UPGRADING.md's symptom index and
   fix it; if nothing matches, follow its "If something else breaks" section.
6. If the project generates RBS with `FieldStruct::RBS.generate`, or with a task that
   wraps it (`rg -n 'FieldStruct::RBS' lib Rakefile`), regenerate it and run Steep if
   the project does.
7. Report: old → new version, each entry that applied (file:line, fix), each Find
   with no hits, and anything left unexplained.

## Fast paths

- Bootstrap a model from a JSON sample: `FieldStruct::Scaffold.from_json(json)`.
- See a model's shape without reading source: `pp Klass.metadata.to_h` (structured), or `puts Klass.describe` (readable — fields, types, and what each accepts).
- Ask a type what options it accepts (name, value shape, presets): `FieldStruct.types.lookup(:date).option_schema`.
- Type your models for Steep/Solargraph: `FieldStruct::RBS.generate(Klass)`.
- "Update" an immutable or frozen instance: `record.with(field: value)` returns a changed copy.
- Payment/API input: `unknown_attributes :raise` on every struct that reads it, `strict: true` on money and id fields, `sensitive: true` on card data. See [USAGE](USAGE.md#payment-and-api-boundaries-unknown_attributes-raise).
