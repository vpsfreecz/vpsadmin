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
