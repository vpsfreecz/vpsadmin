# Built-in mail templates

This directory contains built-in mail template directories in the same format
accepted by `vpsadmin-mail-templates`: each template has its own directory
with `meta.rb` and translated `*.erb` bodies.

Install them with:

```sh
bundle exec rake vpsadmin:mail_templates:install_defaults
```

The installer only creates missing templates and translations. Existing
database content is left unchanged. Template translations use
`core.support_mail` as their default sender and reply address when it is
configured.
