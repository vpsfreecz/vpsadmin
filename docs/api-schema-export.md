# Exporting the API schema

`tools/export-api-schema` produces the declared API 7.0 schema for TypeScript
client generation. It mounts the real API from a clean, committed checkout,
loads all six bundled plugins, and uses the repository's fixture data in a new
temporary MariaDB database. It does not contact a deployed API or database.

The export describes declared operations and parameters. Runtime permissions,
owner restrictions, filtered responses and object-specific action preparation
still apply. The generated schema must not be used as a user's permission set.

## Prepare and export

Enter the normal development shell from the repository root:

```sh
nix develop .#vpsadmin
tools/export-api-schema --prepare
```

Preparation installs a separate tooling bundle with released HaveAPI 0.30.2.
Its Gemfile evaluates the API Gemfile with one checked dependency replacement;
the API and packaged runtime dependencies remain unchanged. The tooling bundle
and its lockfile are ignored local files under `tools/api-schema-export/`.

Commit the intended source changes and pass the database-free checks before
exporting. Choose a destination that does not exist:

```sh
tools/export-api-schema --api-version 7.0 --output /tmp/vpsadmin-schema-export
```

The exporter refuses inherited `DATABASE_URL`, test-database overrides, plugin
directory overrides, Bundler overrides and MySQL/MariaDB connection settings.
It also refuses local API database and configuration files, local Bundler configuration
and alternate `api/plugins` directories. Use a fresh shell without those settings;
do not supply a real database URL. The two tracked configuration files
`dataset_plans.rb` and `dataset_properties.rb` are part of the recorded input.
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
