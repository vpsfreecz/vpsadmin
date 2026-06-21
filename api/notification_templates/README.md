# Built-In Notification Templates

This directory contains built-in notification templates installed by:

```sh
bundle exec rake vpsadmin:notification_templates:install_defaults
```

Template directories live under `templates/`. Each template has `meta.rb` and
one subdirectory per protocol, for example `email/` and `telegram/`.

E-mail variants use `email/<language>.subject.erb`, `email/<language>.text.erb`,
and optionally `email/<language>.html.erb`. Telegram variants use
`telegram/<language>.text.erb`.

The installer only creates missing templates and variants. Existing database
content is left unchanged. E-mail variants use `core.support_mail` as their
default sender and reply address when it is configured.
