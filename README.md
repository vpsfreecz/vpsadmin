# vpsFree.cz specific mail templates for vpsAdmin

This repository contains mail templates for vpsAdmin used at
[vpsFree.cz](http://www.vpsfree.cz). After editing, the templates must be
installed (sent to the API).

## Requirements

 - make
 - Ruby >= 2.0
 - gems specified in `Gemfile`

## Usage

Every template is in a directory. The directory name must match with the
template name. The directory must contain file `meta.rb`. Templates can be
translated to multiple languages and be in plain text or HTML format.

The template directory may contain files with name in format
`<language>.<format>.erb`, e.g. `en.plain.erb` or `en.html.erb`.

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

## Installation

Installation is done by `make`. Optional variables:

 - `API` - the URL of the API to upload templates to
 - `VERSION` - version of the API to use
 - `USERNAME`
 - `PASSWORD`

The user name and password is prompted on stdin if it is not set.

For example:

	$ make API=https://api.vpsfree.cz USERNAME=admin

