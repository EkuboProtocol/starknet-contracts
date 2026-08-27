# AGENTS.md

## Complexity Policy
- **There is no complexity gate for Cairo, and this is a gap rather than a decision.**
- `scarb lint` (cairo-lint, as of Scarb 2.20) ships only style and idiom rules —
  `collapsible_if_else`, `manual_unwrap_or`, `manual_assert`, `redundant_conversion`,
  `bool_comparison`, redundant parentheses, and a nesting hint attached to `if`
  collapsing. There is no cyclomatic or cognitive complexity rule and no threshold
  configuration, so there is nothing to enable here.
- Every other Ekubo repository gates complexity in CI: solhint `code-complexity` for
  Solidity, ESLint `complexity` for TypeScript, `clippy::cognitive_complexity` for
  Rust, ruff `C901` for Python. Cairo is the one language with no equivalent. Do not
  read the absence of a failing check here as the code having been measured.
- `scarb lint` does report real findings today on the style rules it does have. It is
  not wired into CI; running it is worthwhile independently of complexity.
