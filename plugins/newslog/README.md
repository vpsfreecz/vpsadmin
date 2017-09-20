vpsAdmin News Log
=================

This plugin adds support for a simple news log. Admins can publish news and users
can read them.

## Installation
Copy the plugin to directory `plugins/` in your API installation directory.
During the database setup, you can choose to transfer user payment settings
from vpsAdmin 1 by setting environment variable `FROM_VPSADMIN1`.

### Migration from vpsAdmin core
It is possible to migrate from old news log from vpsAdmin 1:

    $ rake vpsadmin:plugins:migrate PLUGIN=newslog FROM_VPSADMIN1=yes

### Clean install

    $ rake vpsadmin:plugins:migrate PLUGIN=newslog

## Changes
This plugin defines new resource `NewsLog`.
