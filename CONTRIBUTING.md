# Contributing to Solo Orchestrator

Thank you for your interest in contributing to the Solo Orchestrator Framework.

## Developer Certificate of Origin (DCO)

All contributions to this project must be signed off under the [Developer Certificate of Origin (DCO) v1.1](https://developercertificate.org/). By adding a `Signed-off-by` line to your commit messages, you certify that you wrote the contribution or otherwise have the right to submit it under the project's MIT license.

### How to Sign Off

Add `--signoff` (or `-s`) to your `git commit` command:

```bash
git commit -s -m "Your commit message"
```

This appends a line like:

```
Signed-off-by: Your Name <your.email@example.com>
```

Every commit in a pull request must include this sign-off. Commits without a DCO sign-off will not be accepted.

### What the DCO Means

```
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.

Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

## What to Contribute

- Bug fixes for `init.sh` or CI/CD pipeline templates
- New language CI templates (following the existing template structure)
- New platform modules (following the existing module structure)
- Documentation corrections and clarifications
- Evaluation prompt improvements

## How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-change`)
3. Make your changes
4. Ensure all commits include DCO sign-off (`git commit -s`)
5. Open a pull request against `main`

## Commit conventions

This project follows [Conventional Commits](https://www.conventionalcommits.org/) for commit subject lines. Use one of the following prefixes:

- `feat` — a new feature or capability
- `fix` — a bug fix
- `docs` — documentation-only changes
- `test` — adding or correcting tests
- `refactor` — code change that neither fixes a bug nor adds a feature
- `chore` — tooling, build configuration, or repository maintenance

An optional scope in parentheses narrows the subject (e.g., `fix(init): handle missing CDF clone`). The subject should be imperative and under ~72 characters; longer rationale belongs in the commit body.

### Docs-only bypass

Commits whose staged files all match documentation extensions (`.md`, `.json`, `.yml`, `.yaml`, `.toml`, `.tmpl`) skip the Build Loop gate. The classifier lives in `scripts/process-checklist.sh` (function `check_commit_ready`, regex `\.(md|json|yml|yaml|toml|tmpl)$`); a matching commit does not need to be tied to an open Build Loop step. Mixed commits (any staged source file alongside docs) fall back to full Build Loop enforcement — split them if you want the docs portion to land without the gate.

Dependency manifests (`Pipfile.lock`, `Gemfile.lock`, `go.sum`, etc.) are also exempt via the `_is_dep_manifest` helper in the same script.

## Local development setup

The framework lives in two repositories — both must be cloned for the test suite and `init.sh` to function end-to-end.

1. Clone the framework:
   ```bash
   git clone https://github.com/kraulerson/solo-orchestrator.git
   ```
2. Clone the Claude Dev Framework to the path `init.sh` expects:
   ```bash
   git clone https://github.com/kraulerson/claude-dev-framework.git ~/.claude-dev-framework
   ```
   The `~/.claude-dev-framework` location is required; see `docs/cli-setup-addendum.md` §3 ("Development Guardrails for Claude Code") for the rationale.
3. Run the test suites directly to validate a working checkout (faster than running `init.sh` against a scratch project):
   ```bash
   bash tests/full-project-test-suite.sh
   bash tests/host-drivers/run-all.sh
   ```
   Alternatively, run `bash init.sh` from a throwaway directory to exercise the full installer flow.
4. Install the pre-commit gate locally (`init.sh` does this for user projects; contributors working on the framework itself must install it manually):
   ```bash
   cp scripts/pre-commit-gate.sh .git/hooks/pre-commit
   chmod +x .git/hooks/pre-commit
   ```

For deeper setup — MCP servers, profiles, CLAUDE.md authoring, host CLI installation — see `docs/cli-setup-addendum.md` and `docs/user-guide.md`.

## What Not to Contribute

- Changes to the core methodology (Builder's Guide phases, governance structure) without prior discussion in an issue
- AI-generated contributions without human review and DCO sign-off — you are certifying the contribution, not the AI
- Dependencies or compiled code — this framework is documentation, scripts, and templates

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
