# Ambxst Agent Guide
- **Run desktop**: `qs -p shell.qml` (requires QuickShell/Qt environment)
- **Single component check**: launch `qs -p modules/widgets/dashboard/Dashboard.qml` for targeted smoke tests
- **Tests**: no automated suite; rely on manual QA focused on touched flows
- **Lint**: none configured; keep QML formatting consistent with Qt Creator defaults
- **Dependencies**: avoid package installs unless user approves; expect local QuickShell toolchain
- **Imports**: order as QtQuick → Quickshell → `qs.modules.*` → project modules → config singletons
- **Pragmas**: use `pragma Singleton` for globals and `pragma ComponentBehavior: Bound` to stabilize bindings
- **Formatting**: 4-space indent, soft-wrap near 100 chars, align multi-line bindings for readability
- **Types**: declare explicit QML types (`property int`, `property alias`); reserve `var` for truly dynamic data
- **Required props**: mark with `required property` and clamp user-configurable values before use
- **Config access**: retrieve settings through `Config` singleton; do not hardcode theme/layout numbers
- **Naming**: files/components PascalCase, ids/properties camelCase, loaders suffixed `Loader`
- **Signals/handlers**: prefer verbNoun naming (`togglePlay`), keep handlers concise and without side effects
- **Error handling**: protect service calls, emit `console.warn` with context, degrade gracefully when data missing
- **State management**: centralize shared state in `globals/GlobalStates.qml`; avoid duplicating timers or models
- **Assets**: sync palette JSON with `Config` expectations
- **Comments**: English only, short notes before non-obvious logic; favor self-explanatory code otherwise
- **Version control**: never revert user work; review `git status` before staging and keep commits scoped
- **Manual validation**: after QML edits reload shell, check bar/dashboard animations, and verify notifications
- **References**:
  - [Quickshell Repository](https://github.com/quickshell-mirror/quickshell)
  - [Illogical Impulse](https://github.com/end-4/dots-hyprland)
  - [Caelestia](https://github.com/caelestia-dots/shell)

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.