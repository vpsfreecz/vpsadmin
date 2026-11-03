# Exporting the API schema

`tools/export-api-schema` produces the declared API 7.0 schema for Go, Rust and
TypeScript client generation. It mounts the real API from a clean, committed
checkout, loads all six bundled plugins, and uses the repository's fixture data
in a new temporary MariaDB database. It does not contact a deployed API or database.

The export describes declared operations and parameters. Runtime permissions,
owner restrictions, filtered responses and object-specific action preparation
still apply. The generated schema must not be used as a user's permission set.
For API work, follow [Generated client synchronization](#generated-client-synchronization)
as part of task completion.

## Prepare and export

Enter the normal development shell from the repository root:

```sh
nix develop .#vpsadmin
tools/export-api-schema --prepare
```

Preparation installs a separate tooling bundle pinned to HaveAPI 0.32.2,
matching the API. Its Gemfile checks the API dependency declaration
and replaces its constraint with that exact version. Preparation leaves the API
and packaged runtime dependencies unchanged. The tooling bundle and its lockfile
are ignored local files under `tools/api-schema-export/`.

Commit the intended source changes and pass the database-free checks before
exporting. Choose a destination that does not exist:

```sh
tools/export-api-schema --api-version 7.0 --output /tmp/vpsadmin-schema-export
```

The exporter refuses inherited `DATABASE_URL`, test-database overrides, plugin
directory overrides, Bundler overrides and MySQL/MariaDB connection settings.
It also refuses local API database and configuration files, local Bundler configuration
and alternate `api/plugins` directories. Use a fresh shell without those settings;
do not supply a real database URL. The tracked configuration files `dataset_plans.rb` and
`dataset_properties.rb` are part of the recorded input. The tracked
`api.rb.example` sample may be present but is never loaded.
The exporter always selects `RACK_ENV=test`, English and all bundled plugins.
Its shell launcher rejects Ruby preload options and active Bundler settings
before starting Ruby, and discards inherited `RUBYLIB`. Run it directly from the
development shell, outside `bundle exec`. The interpreter, executable search path
and build environment must be trusted; the launcher is not a sandbox for hostile
shell commands.

The existing temporary test-database runner owns database startup and shutdown.
It allocates a temporary directory and a free local port and removes its data
when the process exits. No shared development cluster is required. Abrupt process
termination can prevent normal cleanup. Before removing leftover data, identify
the exporter's database process and stop that owned process.

## Output and provenance

The destination contains:

- `schema.json`: the canonical saved schema envelope, with format 1, explicit
  API and protocol versions, profile `vpsadmin-full-fixture`, mount `/`, description
  and synthetic source URL `https://schema.invalid/v7.0/`. The URL is never
  contacted.
- `provenance.json`: the source revision, fixture and configuration hashes, schema
  digest, resource, action and parameter counts, tooling lock and installed gem
  identities, database version, and sorted plugin source and migration inventory.
- `tooling.Gemfile.lock`: the exact dependency resolution used for the export.

Canonical JSON sorts object keys, preserves array order, uses two-space indentation
and ends with one newline. Descriptive prose, examples and protected defaults
are removed in their structural context; parameter names, choice keys and
Custom data remain intact. The snapshot preserves metadata and partial resource
associations for the generator to interpret. Credentials, database URLs, generated
users and tokens do not belong in saved artifacts.

The bootstrap follows the existing API translation-catalog runtime loader. It
loads the core schema, seeds languages, system configuration and cluster resources,
mounts the API, applies actual plugin migrations and loads the normal spec
fixture. It does not import `spec_helper`, install its network stubs or replace
schema/model behavior. The schema records the complete declared fixture profile,
including actions added by plugins and concerns. It does not certify a deployed
installation's configuration or API compatibility.

## Database-free checks

Run these from the repository root after normal API dependency preparation:

```sh
BUNDLE_GEMFILE="$PWD/api/Gemfile" BUNDLE_PATH="$PWD/api/.gems" \
  bundle exec rspec --options /dev/null \
  tools/api-schema-export/safety_spec.rb \
  tools/api-schema-export/snapshot_spec.rb
```

The explicit options file prevents loading `api/.rspec` and its database setup.
These checks cover unsafe input rejection and snapshot sanitization. A real
export and an independent repeated export from another fresh database are
separate checks; passing the unit cases does not establish schema completeness
or reproducibility.

## Generated client synchronization

Every API task must assess [Go](https://github.com/vpsfreecz/vpsadmin-go-client),
[Rust](https://github.com/vpsfreecz/vpsadmin-rust-client) and
[TypeScript](https://github.com/vpsfreecz/vpsadmin-typescript-client), including
behavior-only work. Changes to the exported contract or generated output require
client updates; unchanged clients need evidence against the assessed API revision.
This is a contributor completion requirement; existing saved-input checks do not
enforce API freshness.

1. Export from the final clean, committed API source using the procedure above.
   Retain the raw schema, provenance and tooling lock unchanged, including exact
   source revision, API/protocol versions, plugins, profile, locale and dependency
   identities. Repeat the export from a fresh fixture database when the exporter,
   fixture/profile or tooling changes, or if deterministic output has not been
   established.
   Review profile changes, such as replacing a public capture with the full fixture.
   Pin the HaveAPI generator revision, copied runtime, dependency lock, configuration
   and formatter separately for each client.
2. Regenerate each affected client's owned output using its contributor guide and
   run its applicable checks. Compare the complete generated file set, including
   deletions. Preserve handwritten files. If a client needs an input transformation,
   retain the raw export and record the transformation, its compatibility reason,
   raw and derived digests, owner and reproducibility check. For an unchanged client,
   record the exact API source, schema/profile digest, client head and generator
   identity, the comparison or check performed, and why no generated change is needed.
   A successful check against a saved schema proves consistency with that input;
   current-source comparison establishes freshness.
3. Review action and parameter additions/removals, required inputs, types,
   nullability, generator/runtime pairing and old/new client-server compatibility.
   Generated members do not establish server availability or permissions. Deploy
   compatible API support before enabling new calls, or gate those calls on the
   server's capabilities. Keep backend deployment and client publication as separate
   decisions. Recover client changes by restoring their schema, provenance,
   generator inputs and generated output together; retain published releases.
4. Prepare and check client candidates against the final API feature commit before
   integration. Candidates may use committed feature inputs before those inputs
   reach a default branch. Obtain explicit integration approval for every affected
   repository and target. Integrate clients first where forward compatibility
   permits; otherwise integrate the API and then clients in one bounded approved
   batch. Cross-repository updates are not atomic: a failed integration leaves the
   task incomplete with an owner and next action. Refresh input evidence after a
   rebase or intervening contract change. Complete the task only when every changed
   client's final head is in its remote default branch and every unchanged client
   has the revision-specific no-change evidence above. Client updates cannot be
   left as an open follow-up to a completed API task.

Ordinary generated-client synchronization requires no version bump, tag or package
publication. Follow each client's release procedure when a release is needed.
A TypeScript-client release defaults to the next minor version; an explicit user
version or bump instruction overrides that default. State incompatible changes and
their consumer impact before proceeding.

A WebUI change that needs new API support through `vpsadmin-typescript-client`
requires a published TypeScript-client release containing that support before the
WebUI change is merged. Feature-branch, Git and local dependencies are allowed
during development. Before merge, the final WebUI manifest and lock must resolve
the published registry artifact, with temporary overrides removed. Record the
required generated members, release version and resolved integrity. Synchronization,
integration, publication and backend capability readiness remain distinct checks;
this procedure does not authorize merges, releases or deployments.
