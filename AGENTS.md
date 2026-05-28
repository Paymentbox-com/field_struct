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
- `skills/field-struct/SKILL.md` — the bundled Claude Code skill.

## The five gotchas

1. **Setters are permissive** — `user.age = "30"` is valid (the type coerces). Don't "fix" it.
2. **`required` ≠ non-nil at runtime** — an invalid instance can hold `nil`. Gate on `valid?`.
3. **Whitespace-only strings count as missing** for `:string` and its subtypes.
4. **`:array` needs `of:`; `:union` needs `of: [...]`** (≥2 members).
5. **Option scoping**: `format:`→string/date-ish, `enum:`→string/symbol, `in:`→numeric/temporal, `round:`→float/decimal, `values:`→boolean.

## Fast paths

- Bootstrap a model from a JSON sample: `FieldStruct::Scaffold.from_json(json)`.
- See a model's shape without reading source: `pp Klass.metadata.to_h`.
- Type your models for Steep/Solargraph: `FieldStruct::RBS.generate(Klass)`.
