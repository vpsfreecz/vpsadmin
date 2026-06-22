# Built-in notification templates

vpsAdmin uses the templates in `templates/` when it initializes a database.
Each template has this structure:

```text
templates/<name>/meta.rb
templates/<name>/email/<language>.subject.erb
templates/<name>/email/<language>.text.erb
templates/<name>/email/<language>.html.erb
templates/<name>/telegram/<language>.text.erb
templates/<name>/telegram/<language>.html.erb
templates/<name>/sms/<language>.text.erb
```

`meta.rb` defines the template ID, label, visibility, sender addresses, and
language-specific defaults. E-mail variants need a text or HTML body. Their
subject can come from a subject file, metadata, or vpsAdmin's default.
Telegram variants need a text body and may also provide HTML.
SMS variants need a text body.

Despite its filename, `meta.rb` uses a restricted literal DSL and is never
evaluated as Ruby. It accepts `template`, `protocol`, `lang`, and documented
property declarations. Method calls, interpolation, and computed values are
rejected. Language codes are normalized two-letter codes.

Check a template tree with:

```sh
nix run .#notification-template-check -- api/notification_templates/templates
```

The database setup service creates missing built-in templates and variants.
Existing database content is left unchanged. When
`vpsadmin.api.notificationTemplates.source` is set, vpsAdmin overlays it on the
built-in templates. A dedicated service then keeps matching database rows in
sync.
