# vpsAdmin Notification Templates

Utility for installing notification templates from files to the API.

## Usage

```sh
vpsadmin-notification-templates --help
vpsadmin-notification-templates https://api.example install
```

Run the command from a repository containing a `templates/` directory.

## Layout

Each template lives in `templates/<name>/`:

```text
templates/
  user_create/
    meta.rb
    email/
      en.subject.erb
      en.text.erb
      en.html.erb
      cs.subject.erb
      cs.text.erb
    telegram/
      en.text.erb
      en.html.erb
      cs.text.erb
```

E-mail variants support `subject`, `text`, and `html` parts. Telegram variants
support required `text` and optional `html` parts. When a Telegram HTML part is
present, vpsAdmin sends it with Telegram HTML parse mode and keeps the text part
as the fallback.

## `meta.rb`

`meta.rb` is Ruby evaluated by the uploader. Use `template` to bind the
directory to a registered vpsAdmin template id and to set metadata:

```ruby
template :user_create do
  label 'User created'

  protocol :email do
    lang :en do
      from 'support@example.org'
      reply_to 'support@example.org'
      return_path 'support@example.org'
    end
  end
end
```

The available template-level options are `label` and `user_visibility`.

The available variant options are `from`, `reply_to`, `return_path`, `subject`,
and `options`. Variant options can be set globally, inside `protocol`, or inside
`lang`.
