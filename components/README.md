# Components

The component repositories are cloned into this directory. Each is its own git repository, ignored by
`assistant-link`. If it is empty, clone them from the repository root:

```sh
mise run clone
```

or run [`scripts/clone`](../scripts/clone) directly. See [docs/getting-started.md](../docs/getting-started.md).

| Directory  | Repository                                                     | What it is                                                     |
| ---------- | -------------------------------------------------------------- | -------------------------------------------------------------- |
| `backend/` | [assistant-link/backend](https://github.com/assistant-link/backend) | The service (Elixir/Phoenix), the ALP spec, and self-hosting. |
| `cli/`     | [assistant-link/cli](https://github.com/assistant-link/cli)         | `al`, the agent-side command-line tool (Rust).                |
| `apple/`   | [assistant-link/apple](https://github.com/assistant-link/apple)     | The iPhone app (SwiftUI). Later also macOS and watchOS.       |
