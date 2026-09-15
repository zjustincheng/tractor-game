# Repository Guidelines

## Project Structure & Module Organization

This repository (`tractor-game`) is currently an empty Git repository. No application code, tests, assets, or dependency manifests have been added yet. Update this guide as the project takes shape.

When introducing the initial implementation, keep source code, tests, and game assets clearly separated. Suggested directories are `src/`, `tests/`, and `assets/`; adapt these to the chosen framework. Add a `README.md` describing the game, prerequisites, and local setup.

## Build, Test, and Development Commands

No build system, development server, or test runner is configured. Do not assume commands such as `npm test` or `make build` are available.

When adding tooling, document the exact installation, development, build, and test commands in `README.md`. Prefer repository-defined scripts so contributors and automation use the same commands. Commit the appropriate dependency lockfile when supported.

## Coding Style & Naming Conventions

No language, indentation standard, formatter, or linter has been selected. Follow the conventions of the chosen language and framework, and configure formatting and linting alongside the first implementation.

Use descriptive names for modules, functions, and assets. Keep each module focused on one responsibility. Avoid mixing unrelated refactoring with feature changes.

## Testing Guidelines

There is no testing framework or coverage threshold yet. Introduce tests with meaningful game logic, following the selected framework's file naming conventions. Document how to run them, and favor deterministic tests for rules and state changes. For visual or interactive changes, record the manual checks performed.

## Commit & Pull Request Guidelines

There is no commit history from which to infer conventions. Use concise, imperative commit subjects, such as `Add tractor movement controls`, and keep commits focused.

Pull requests should explain the change, list verification performed, and link relevant issues when available. Include screenshots or short recordings for visible gameplay or interface changes. State any setup changes or known limitations.

## Security & Configuration

Do not commit secrets, local credentials, generated build output, or installed dependencies. Add appropriate `.gitignore` rules when introducing tooling, and document required configuration with safe example values.
