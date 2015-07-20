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
template name. The directory must contain file `meta.rb` and may contain files
`plain.erb` for plain text version and `html.erb` for HTML version.

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

## Installation

Installation is done by `make`. Optional variables:

 - `API` - the URL of the API to upload templates to
 - `VERSION` - version of the API to use
 - `USERNAME`
 - `PASSWORD`

The user name and password is prompted on stdin if it is not set.

For example:

	$ make API=https://api.vpsfree.cz USERNAME=admin

