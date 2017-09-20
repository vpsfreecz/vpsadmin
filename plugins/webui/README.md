vpsAdmin web UI support
=======================

This plugin adds support for web UI-specific API endpoints, so far only help
boxes.

## Installation
Copy the plugin to directory `plugins/` in your API installation directory.
During the database setup, you can choose to transfer help boxes
from vpsAdmin 1 by setting environment variable `FROM_VPSADMIN1`.

### Migration from vpsAdmin core
It is possible to migrate from old help boxes from vpsAdmin 1:

    $ rake vpsadmin:plugins:migrate PLUGIN=webui FROM_VPSADMIN1=yes

### Clean install

    $ rake vpsadmin:plugins:migrate PLUGIN=webui

## Changes
This plugin defines new resource `HelpBox`.
