# vpsAdmin Mail Templates

Utility for installing mail templates from text files to the API.

## Requirements

 - Ruby >= 2.0
 - gems specified in `Gemfile`

## Usage

    $ vpsadmin-mail-templates --help
    Usage: vpsadmin-mail-templates [options] <api> <action>

    Actions:
        auth                             Authenticate and exit
        install                          Upload templates to the API

    Options:
        -a, --auth AUTH                  Basic or token authentication
        -u, --user USER                  Username
        -p, --password PASSWORD          Password
        -t, --token TOKEN                Token
        -i, --token-lifetime LIFETIME    Token lifetime
        -s, --save-token [FILE]          Save token to FILE
        -l, --load-token [FILE]          Load token from FILE
        -h, --help                       Show this help

`vpsadmin-mail-templates` has to be run from the directory containing the
templates.

## Templates

Every template is in a subdirectory whose name is the template name.
The template directory must contain file `meta.rb`. Templates can be translated
to multiple languages and be in plain text or HTML.

The template directory may contain files with names in format
`<language>.<format>.erb`, e.g. `en.plain.erb` or `en.html.erb`.

For example usage, see
[vpsfree-mail-templates](https://github.com/vpsfreecz/vpsfree-mail-templats).

## `meta.rb` format
It is a standard Ruby file. There is one predefined method `template`. It has no
arguments and accepts a block. The block is executed in an environment with
methods (options) `label`, `from`, `reply_to`, `return_path` and `subject`.
All these methods accept one argument. They are used to describe the template.

Required options are `label`, `from`, `subject`.

For example:

```ruby
template do
  label        'Some Label'
  from         'vpsadmin@vpsfree.cz'
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Some Subject'
end
```

It is possible to specify `from`, `reply_to`, `return_path` and `subject` per
language, e.g.:

```ruby
template do
  label        'Some Label'
  # `from` is the same for all languages, so mention it only here
  from         'vpsadmin@vpsfree.cz'

  # The following options are overriden by options set for languages.
  # We may set some defaults.
  reply_to     'podpora@vpsfree.cz'
  return_path  'podpora@vpsfree.cz'
  subject      '[vpsFree.cz] Some Subject'

  lang :en do
    reply_to     'support@vpsfree.cz'
    return_path  'support@vpsfree.cz'
    subject      '[vpsFree.cz] Some Subject'
  end
  
  lang :cs do
    reply_to     'podpora@vpsfree.cz'
    return_path  'podpora@vpsfree.cz'
    subject      '[vpsFree.cz] Nejaky predmet'
  end
end
```
