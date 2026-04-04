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

## What Not to Contribute

- Changes to the core methodology (Builder's Guide phases, governance structure) without prior discussion in an issue
- AI-generated contributions without human review and DCO sign-off — you are certifying the contribution, not the AI
- Dependencies or compiled code — this framework is documentation, scripts, and templates

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
