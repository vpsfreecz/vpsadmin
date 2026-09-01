# Built-in notification templates

vpsAdmin uses the templates in `templates/` when it initializes a database.
Each template has this structure:

```text
templates/<name>/meta.rb
templates/<name>/email/<language>.subject.erb
templates/<name>/email/<language>.text.erb
templates/<name>/email/<language>.html.erb
```

`meta.rb` defines the template ID, label, visibility, sender addresses, and
language-specific defaults. Each language needs a text or HTML body. The
subject can be supplied by a subject file, metadata, or vpsAdmin's default.
Despite the filename, metadata uses a restricted literal DSL, not executable
Ruby. It accepts the documented `template`, `lang`, and property declarations;
method calls, interpolation, and computed values are rejected. Language codes
are normalized two-letter codes.

Check a template tree with:

```sh
nix run .#notification-template-check -- api/notification_templates/templates
```

The database setup service creates missing built-in templates and
translations. Existing database content is left unchanged. When
`vpsadmin.api.notificationTemplates.source` is set, vpsAdmin overlays it on the
built-in templates. A dedicated service then keeps matching database rows in
sync.
