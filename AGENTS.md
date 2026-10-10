# Agents

This is the Assistant Link workspace. `components/backend/`, `components/cli/`, and `components/apple/` are separate
git repositories, cloned there by `scripts/clone` and ignored by this one. Each has its own `AGENTS.md` with its rules
and quality gate; follow it when you work there.

Follow [docs/engineering/how-to-make-changes.md](docs/engineering/how-to-make-changes.md) for how to make a change.

- Every change is planned in this repository's `openspec/`, including a change to a single component, with tasks
  grouped by repository. The component repositories have no `openspec/` of their own; run `openspec` from anywhere in
  this workspace and it finds this one.
- `mise.toml` here pins every tool the components need. When a component changes a pin in its own `mise.toml`, change
  it here too.
- `mise run test:integration` runs the components together (see `tests/integration/README.md`).

## Rules

- Comment only what the code cannot show: never restate what the code does.
