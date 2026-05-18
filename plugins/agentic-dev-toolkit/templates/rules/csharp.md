---
paths:
  - "**/*.cs"
---

# C# Conventions

- Prefix all instance member access with `this.` (properties, methods, fields, events)
- Regular `//` comments are fine where logic isn't self-evident
- XML doc comments (`/// <summary>`, etc.) are repo-dependent — follow the repo's StyleCop/`.editorconfig` and the surrounding file's pattern. Do not add or remove them on a global rule.
- Use `string.Empty` instead of `""` for empty strings (SA1122)
- Pass `CultureInfo.InvariantCulture` to `.ToString()` on numeric types (CA1305)
- Avoid reserved language keywords in namespace segments — e.g. `Shared`, `Module`, `Event` (CA1716)
- No blank line before a closing brace `}` (SA1508)
- Use null-safe casts for nullable value types — `(int?)x.Prop ?? 0` not `(int)x.Prop` (CS8629)
