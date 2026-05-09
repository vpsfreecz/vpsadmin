# Built-in mail templates

This directory may contain built-in mail template directories in the same
format accepted by `vpsadmin-mail-templates`: each template has its own
directory with `meta.rb` and translated `*.erb` bodies.

The API also generates neutral English fallbacks for registered templates that
do not have a checked-in directory here yet. Install them with:

```sh
bundle exec rake vpsadmin:mail_templates:install_defaults
```

The installer only creates missing templates and translations. Existing
database content is left unchanged.
