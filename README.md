# Assistant Link

Assistant Link gives you a persistent mobile connection to your own AI assistants. An iPhone app talks to an
Assistant Link service, and the agent connects outbound to the same service, so the agent host needs no VPN, public
IP, or open port. See [docs/product/high-level-spec.md](docs/product/high-level-spec.md) for the product.

```
agent runtime  <-- ALP -->  Assistant Link service  <-->  iOS app
```

This repository is the entry point to the project. Each component lives in its own repository:

| Repository                                                | What it is                                                                     |
| --------------------------------------------------------- | ------------------------------------------------------------------------------ |
| [backend](https://github.com/assistant-link/backend)      | The service: one Phoenix app (Elixir) on Postgres. Also the [ALP spec](https://github.com/assistant-link/backend/blob/main/docs/alp/v1.md) and [self-hosting](https://github.com/assistant-link/backend/blob/main/deploy/SELF_HOSTING.md). |
| [apple](https://github.com/assistant-link/apple)          | The iPhone app (SwiftUI). Later also macOS and watchOS.                        |
| [cli](https://github.com/assistant-link/cli)              | `al`, the agent-side command-line tool (Rust).                                 |

This repository holds what spans them:

- [`scripts/clone`](scripts/clone): clones the component repositories into this one, so you work on all of them from
  a single directory.
- [`tests/integration/`](tests/integration/): tests that run the components together.
- [`openspec/`](openspec/): proposals for changes that span several components, planned with
  [OpenSpec](https://github.com/Fission-AI/OpenSpec). A change to one component is proposed in that component's own
  `openspec/`.
- [`docs/`](docs/): the [product spec](docs/product/high-level-spec.md), [product Q&A](docs/product/qa.md), and
  [engineering principles](docs/engineering/principles.md).

## Getting started

```sh
git clone https://github.com/assistant-link/assistant-link.git
cd assistant-link
mise trust && mise install
mise run clone
```

[docs/getting-started.md](docs/getting-started.md) has the prerequisites and how to run everything together locally.

The hosted service runs at <https://assistant-link.fly.dev>; the app and `al` use it by default, and each can be
pointed at a local or self-hosted service instead.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) (every commit needs a DCO sign-off), and report
vulnerabilities as described in [SECURITY.md](SECURITY.md).

The code in every Assistant Link repository is licensed under the [MIT License](LICENSE). The Assistant Link name and
app icon are not; see [TRADEMARK.md](TRADEMARK.md).
