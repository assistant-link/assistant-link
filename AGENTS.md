# Agents

This is the Assistant Link workspace. `backend/`, `cli/`, and `apple/` are separate git repositories, cloned here by
`scripts/clone` and ignored by this one: commit, branch, and open pull requests in each repository on its own. Each has
its own `AGENTS.md` with its rules and quality gate; follow it when you work there.

- A change to one component is planned in that component's `openspec/`. A change that spans components is planned in
  this repository's `openspec/`, with tasks grouped by repository.
- `mise.toml` here pins every tool the components need. When a component changes a pin in its own `mise.toml`, change
  it here too.
- `mise run test:integration` runs the components together (see `tests/integration/README.md`).

## Rules

- Comment only what the code cannot show: never restate what the code does.
