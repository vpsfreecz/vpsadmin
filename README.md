vpsAdmin Payments
=================

This plugin adds support for paying users. Each user has a monthly payment set
and a paid until date. The plugin is able to fetch transaction from bank accounts
(currently only FIO bank) and assign incoming payments to users, extending their
account.

## Currencies
There is one default currency in which all payments are accepted. For other
currencies, there is a static conversion rate table, so that you can configure
fixed prices in all currencies.

## Installation
Copy the plugin to directory `plugins/` in your API installation directory.
During the database setup, you can choose to transfer user payment settings
from vpsAdmin 1 by setting environment variable `FROM_VPSADMIN1`.

Transfer from vpsAdmin 1:
    $ rake vpsadmin:plugins:migrate PLUGIN=payments FROM_VPSADMIN1=yes

Clean install:
    $ rake vpsadmin:plugins:migrate PLUGIN=payments
