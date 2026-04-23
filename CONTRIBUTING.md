# Contributing

Thanks for helping improve `ssh-passwordless-installer`.

## What makes a good contribution

- Cross-platform compatibility fixes for macOS or Windows
- Safer SSH onboarding flows
- Better release packaging and documentation
- Clear bug reports with reproducible steps

## Development rules

- Do not commit build artifacts from `build/`
- Do not include real passwords, private keys, or server details in issues or pull requests
- Keep the user-facing flow beginner-friendly and double-click oriented
- Preserve the managed-block approach in `~/.ssh/config` so reruns stay predictable

## Local checks

Run the lightweight checks before opening a pull request:

```bash
bash -n scripts/macos/setup-passwordless-ssh.command
bash -n tools_build_macos_apps.sh
bash -n tools_build_release_bundles.sh
rg -n "^## (Features|Quick Start|License|Author)$" README.md
rg -n "^## (功能亮点|快速开始|许可证|作者)$" README_CN.md
```

If you can test on real machines, also verify:

1. key generation or reuse works for a new alias
2. the public key install step succeeds
3. the managed SSH config block stays idempotent
4. alias login succeeds after setup

## Pull request checklist

- Describe the user-visible change
- Mention the platform you tested on
- Call out any release note or README updates
- Keep secrets and infrastructure details fully redacted
