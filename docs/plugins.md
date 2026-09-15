# Plugins

Plugins extend the API with optional features such as payments, monitoring,
and outage reports. A plugin can define models, API resources, transaction
chains, hooks, and its own database migrations. Existing examples live in
[plugins/](../plugins/).

## Layout and loading

A typical API plugin has this layout:

```text
plugins/example/
  meta.rb
  api/
    Gemfile
    init.rb
    db/migrate/
    lib/
    models/
    resources/
```

`meta.rb` registers the plugin and declares its components. For example:

```ruby
VpsAdmin::API::Plugin.register(:example) do
  name 'Example'
  description 'Example API extension'
  version '0.1.0'
  components :api
end
```

The loader reads the metadata and configures it for the component being loaded.
For an API plugin, a `config` block can register settings and other API
extensions; see the [payments metadata](../plugins/payments/meta.rb).

If `api/init.rb` exists, it controls loading. Otherwise, the loader requires
files recursively from `api/lib`, `api/models`, and `api/resources`, in that
order. A plugin's additional gem dependencies belong in its `api/Gemfile`,
which the API's [Gemfile](../api/Gemfile) evaluates.

Source: [plugin registration](../api/lib/vpsadmin/api/plugin.rb) and
[loader](../api/lib/vpsadmin/api/plugin/loader.rb).

## Selecting plugins

`VPSADMIN_PLUGIN_DIR` selects a plugin directory. A relative path is resolved
against the API root. If it does not name an existing directory, the loader
falls back to `api/plugins/`, then the repository's `plugins/` directory.

`VPSADMIN_PLUGINS` controls which plugins load:

- Unset, empty, or `all`: load the plugins found in the selected directory.
- `none`: disable plugins.
- A comma-separated list: load only those plugin directory names.

Use a consistent selection for the API process and its database maintenance
tasks. Disabling a plugin does not undo its database migrations.

## Database migrations

Plugins have migration files under `api/db/migrate/`. The API tracks their
migration versions separately from core migrations using the plugin ID.

These tasks load the API and require an initialized database configured through
`DATABASE_URL` or `api/config/database.yml`. From the repository root, enter
the API development shell and list the available tasks and loaded plugins:

```sh
nix develop .#api
bundle exec rake -T vpsadmin:plugins
bundle exec rake vpsadmin:plugins:list
bundle exec rake vpsadmin:plugins:status PLUGIN=payments
```

To apply the selected plugin's pending migrations to the configured database:

```sh
bundle exec rake vpsadmin:plugins:migrate PLUGIN=payments
```

Without `PLUGIN`, the migrate task applies migrations for all loaded plugins.
The rollback task takes `PLUGIN` and an optional `STEP` count. The uninstall
task rolls back all migrations for that plugin; it can remove the plugin's
data. Check the migration code and the target database before running either.

Keep plugin tables out of the core `api/db/schema.rb`. Generate the core schema
with `VPSADMIN_PLUGINS=none`; plugin schemas belong to their migration files.

Source: [plugin tasks](../api/lib/vpsadmin/api/tasks/plugin.rb) and
[migrator](../api/lib/vpsadmin/api/plugin/migrator.rb).
