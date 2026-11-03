# Agents

This is the Assistant Link workspace. `components/backend/`, `components/cli/`, and `components/apple/` are separate
git repositories, cloned there by `scripts/clone` and ignored by this one. Each has its own `AGENTS.md` with its rules
and quality gate; follow it when you work there.

Follow [docs/engineering/how-to-make-changes.md](docs/engineering/how-to-make-changes.md) for how to make a change.

- Plan every change as a short task list (checkboxes) in its pull request description, grouped by repository. Write
  tests first and keep PRs small, stacked when useful.
- `mise.toml` here pins every tool the components need. When a component changes a pin in its own `mise.toml`, change
  it here too.
- `mise run test:integration` runs the components together (see `tests/integration/README.md`).

## Rules

- Comment only what the code cannot show: never restate what the code does.
