# Contributing to agent-ruby

Thanks for helping improve the Forest Ruby agent. This guide covers how to report an issue, set up the repository, and get a pull request merged.

## Before you start

- **Found a bug?** Open an issue with the template: expected behavior, actual behavior, logs, and the gem versions you use.
- **Found a security issue?** Do not open a public issue. Follow the [security policy](https://github.com/ForestAdmin/.github/blob/main/SECURITY.md).
- **Planning a large change?** Open an issue first to discuss it, so your work fits the agent's direction before you write it.

## Setup

This monorepo holds one gem per folder in [`packages/`](./packages). Ruby `>= 3.0` is required.

```bash
bundle install
```

A complete demo application lives in [`packages/_examples/demo`](./packages/_examples/demo) to try your changes end to end.

## Tests and lint

Tests run per package:

```bash
cd packages/<package>
BUNDLE_GEMFILE=Gemfile-test bundle install
BUNDLE_GEMFILE=Gemfile-test bundle exec rspec --color --format doc
```

Lint, from the repository root:

```bash
bundle exec rubocop
```

Tests must pass and RuboCop must be clean before you open a pull request.

## Commit messages

Commits follow the [Conventional Commits](https://www.conventionalcommits.org/) specification, checked by the Overcommit hook (`<type>(<scope>): <subject>`). Releases and changelogs are generated from them, so the type matters:

- `fix(datasource_active_record): handle null dates` → patch release
- `feat(agent): add the X option` → minor release
- `docs: ...`, `test: ...`, `chore: ...` → no release

## Pull requests

1. Fork the repository and create a branch from `main`.
2. Make your change, with tests.
3. Give the pull request a Conventional Commits title and fill in the template checklist.
4. The CI must be green. The Forest team reviews every pull request before merging.

## Code of conduct

Everyone taking part in this project is expected to follow the [code of conduct](https://github.com/ForestAdmin/.github/blob/main/CODE_OF_CONDUCT.md).
