# How to make changes in Assistant Link

Assistant Link is built from several components. Each has its own repository and its own release cadence. Multiple versions of those components need to work while releases are rolled out. This is true for both continuously-released components like the `backend` as well as components that need users to update their versions like `al` and the iOS app.

The `main` branch of each repo must be releasable and stable, meaning it integrates well with other Assistant Link components as they are. To achieve this, the `assistant-link`'s `integration-gate` GHA workflow is triggered to run CI for a specific PR with all other components on `main`. That CI check posts back a required check to the PR.


## Multiple PRs

If the change only spans one repository and is not linked to any openspec changes, open a single PR in the component's repo directly.

If the change has openspec changes or is doing related work in several repositories, create a parent PR in assistant-link repo. If the change has no changes in assistant-link you can fall back to using a parent issue.

If the change needs multiple PRs, try to match the branch's name between `assistant-link` and the repos.

Sometimes you will need to merge or even release a PR as part of delivering a change. This often happens when one component has to be released for the other to be tested or verified. That is not a problem, each PR in each repo can merge on its own as long as it passes the `integration-gate` workflow. This allows thoughtful and gradual releases of infrastructure, DB and backend changes.

The merge of the integration tests in `assistant-link` makes sure the implemented functionality will not break from other PRs.

For a multi-PR change, always ensure that all related PRs were concluded.