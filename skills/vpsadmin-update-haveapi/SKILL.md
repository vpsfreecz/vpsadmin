---
name: vpsadmin-update-haveapi
description: Update vpsAdmin's Ruby HaveAPI dependencies to a requested released version. Use when Codex needs to bump haveapi/haveapi-client constraints in vpsAdmin Gemfiles or gemspecs, regenerate package Gemfile.lock and gemset.nix files with tools/bundix_all.sh, and prepare the dependency update for review.
---

# vpsAdmin Update HaveAPI

## Workflow

Run the bundled script from the vpsAdmin repository root:

```bash
nix develop -c skills/vpsadmin-update-haveapi/scripts/update_haveapi.py 0.28.4
```

The script updates the source Ruby dependency declarations for:

- `api/Gemfile`
- `download_mounter/Gemfile`
- `plugins/outage_reports/utils/Gemfile`
- `client/vpsadmin-client.gemspec`
- `mail_templates/vpsadmin-mail-templates.gemspec`

It then runs `tools/bundix_all.sh`, which regenerates the packaged Ruby
Gemfiles, lockfiles, and Nix gemsets under `packages/`.

## Checks

After the script finishes:

- Review `git diff --stat` and confirm only the expected Ruby dependency and
  generated package files changed.
- Run `git diff --check`.
- Run focused checks that are appropriate for the consuming change.

## Web UI And JS

This skill covers the Ruby HaveAPI gems and Nix gemsets. If the same release
also published PHP or JavaScript client artifacts, update the web UI Composer
package and bundled JS client in a separate step or commit, following the
existing vpsAdmin release history.
