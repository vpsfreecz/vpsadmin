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

## Changes
This plugin defines three new resources:

- `IncomingPayment` - all incoming payments from the bank account
- `UserAccount` - per-user payment-related settings
- `UserPayment` - accepted user payments, may be created from `IncomingPayment`

## Usage
To fetch incoming payments from the bank, use rake task `vpsadmin:payments:fetch`:

    $ rake vpsadmin:payments:fetch BACKEND=fio

Now, the tasks are stored in the DB queue. The queue can be processed by rake task
`vpsadmin:payments:process`:

    $ rake vpsadmin:payments:process

These two tasks can be run at once with task `vpsadmin:payments:accept`:

    $ rake vpsadmin:payments:accept BACKEND=fio
