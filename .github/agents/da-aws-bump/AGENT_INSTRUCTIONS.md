# AGENT_INSTRUCTIONS — da-aws schema bump

You are extending the typed Terraform schema of
`dynatrace_aws_monitoring_configuration` to match a newer version of the
`com.dynatrace.extension.da-aws` extension schema. **Read this file in
full before touching any code.**

The repo-level rules in [`/.github/copilot-instructions.md`](../../copilot-instructions.md)
also apply. This file adds task-specific procedure and stop conditions.

---

## 0. Inputs you will receive in the issue body

- `old_version`, `new_version` — semver strings
- `schema_diff.json` — output of `schema_diff.py`, with two top-level
  keys: `added` and `modified`. Each entry is
  `{ "path": "/properties/aws/.../foo", "before": <node|null>, "after": <node> }`.
- Links to the old and new full schema JSON (as workflow artifacts).

There is **no other source of truth**. Do not browse the web for
"AWS extension fields". Do not infer fields from CloudFormation or
`dtctl` source. Everything you add must trace back to a path in
`schema_diff.json`.

## 1. Files you may modify (whitelist)

See [`ALLOWED_PATHS.txt`](./ALLOWED_PATHS.txt). Editing anything outside
that list is an automatic abort. In particular:

- You **may** add a new file under
  `provider/dynatrace/api/extensions/dac/awsmonitoring/settings/`
  (one new file per new sub-type — never bundle two sub-types in one file).
- You **may** modify `settings.go`, `settings_test.go`, and the existing
  sub-type files.
- You **may** modify `extension-versions/da-aws.json` (bump `version` and
  `schema_sha256`, never invent the hash — copy it from the workflow log).
- You **may not** modify `service.go` unless the schema delta requires a
  new endpoint (it almost never does — schema deltas are field-level).
- You **may not** modify `provider/provider.go`, `go.mod`, `go.sum`, any
  file outside `provider/dynatrace/api/extensions/dac/awsmonitoring/`
  except the pin file above.

## 2. Decision procedure (deterministic, follow in order)

For each entry in `schema_diff.json`:

### 2.1 Classify the change

| `before` | `after.type` | `after.deprecated` | Action |
|---|---|---|---|
| `null` | scalar (string/bool/int/float/enum) | false | **Add attribute** to `settings.go` |
| `null` | object | false | **Create new sub-type file**, add block to `settings.go` |
| `null` | array of scalar | false | **Add `TypeList`/`TypeSet` of scalar** to `settings.go` |
| `null` | array of object | false | **Create new sub-type file**, add repeatable block |
| non-null | same type, expanded enum | false | **Extend `ValidateFunc`** with new enum values |
| non-null | same type, narrowed enum | false | **STOP — breaking change.** See §4. |
| non-null | different type | false | **STOP — breaking change.** See §4. |
| any | any | true | **STOP — deprecation needs human review.** See §4. |

### 2.2 Required/Optional

Read `after.required` and `after.computed_by_server` from the diff entry.
- `required: true` → `Required: true`
- `required: false` and server can supply a default → `Optional: true, Computed: true`
- `required: false` and no server default → `Optional: true`

Add a comment above the attribute with the JSON Pointer:

```go
// schema: /properties/aws/properties/foo (required, enum)
```

### 2.3 List vs set

- If `after.x-order-significant: true` (or the field name is `regions`,
  `aggregations`, or anything ordered by the API echo) → `TypeList`.
- Otherwise → `TypeSet`.

### 2.4 Naming

- Go field: PascalCase (`MyField`).
- HCL attribute: snake_case (`my_field`).
- Wire JSON tag in `MarshalJSON` / `UnmarshalJSON`: exactly the schema
  key from the diff (typically camelCase, e.g. `myField`). Never guess.

### 2.5 Round-trip tests

For each new attribute, append to `settings_test.go`:

1. An HCL round-trip case. Pattern: existing `TestSettings_HCLRoundtrip`
   subtests — copy the closest one and adapt.
2. A wire-shape pinning case with a raw JSON literal containing the new
   field. Pattern: existing `TestSettings_JSONRoundtrip`.

If a test helper does not yet exist for the kind of value you are
adding, **do not invent one** — file the case inline.

## 3. Verification loop

After every code change:

```bash
.github/agents/da-aws-bump/verify.sh
```

If it fails, fix only what the output points at. Do not refactor
unrelated code. If three consecutive runs fail, stop and write a comment
on the PR with the last `verify.sh` output verbatim.

## 4. Stop conditions (do **not** code around these)

When any of the following holds, push what you have so far, then add a
PR comment starting with `@maintainer NEEDS REVIEW:` and stop:

- Schema diff contains a *type change* on an existing field.
- Schema diff contains a *narrowed enum* (existing values removed).
- Schema diff contains a *deprecated* field.
- A required field has been added — existing user configs will break;
  the maintainer must decide on a migration story.
- `verify.sh` fails 3× and you cannot diagnose the cause from its output
  alone.

## 5. PR shape

- Title: `chore(da-aws): bump extension schema <old> -> <new>`
- Description must contain, in this order:
  1. Bullet list `Added attribute: <hcl_name>  (schema: <json_pointer>)`
  2. Bullet list `Extended enum: <hcl_name>  (added: <values>)`
  3. Code block with `extension-versions/da-aws.json` diff
  4. Code block with last `verify.sh` output (must end with `OK`)
- Label: `needs-human-review`
- State: **draft** (never ready-for-review automatically)
- Do not enable auto-merge. Do not request reviewers.

## 6. Anti-patterns the verifier will reject

Listed in [`forbidden-patterns.txt`](./forbidden-patterns.txt). The most
common ones the agent gets wrong:

- Reaching for `map[string]interface{}` "just for one field"
- Using `schema.TypeString` for an enum without `ValidateFunc`
- Adding `Required: true` for a field that the server may echo with a
  default (causes plan drift)
- Combining two new sub-types into a single file because they "feel
  related"
- Adding tests that only assert on `MarshalHCL` without the reverse
  `UnmarshalHCL` pass — those tests do not catch the round-trip bugs we
  actually ship
