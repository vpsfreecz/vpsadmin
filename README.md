vpsAdmin Outage Reports
=======================
This plugins adds support for outage reporting. It's possible to report
outages of the entire cluster, environments, locations and nodes. Affected
users are informed via e-mail. Admins can also post updates, to let the users
know how the outage resolution progresses.

## Installation
Copy the plugin to directory `plugins/` in your API installation directory
and setup the database.

    $ rake vpsadmin:plugins:migrate PLUGIN=outage_reports

### Importing outages from the outage-list
At vpsFree.cz, we've been reporting outages to the outage mailing list. All
these mails have the same form, so it is possible to parse them and import
them to the database. `utils/import_outage_list.rb` imports all outages in
the given format from mailman archives to the database.

    # Change directory to the mailman archive for the chosen list:
    $ cd /var/lib/mailman/archives/public/outage-list

    # Get the import script, install its dependencies and then run it:
    $ ./import_outage_list.rb https://api.vpsfree.cz admin

## Changes
This plugin defines five new resources:

- `Outage` - outage reports
- `OutageUpdate` - updates of reported outages
- `UserOutage` - browse users affected by outages
- `VpsOutage` - browse VPS affected by outages
- `VpsOutageMount` - browse affected mounts

## Usage
Outages are reported using action `Outage.Create`. Outages can be in one
of the following states: staged, announced, closed or cancelled. After creation,
it's in the staged state. Staged outages are visible only to admins.

Entities affected by the outage are registered using `Outage.Entity.Create`.
Admins working on resolving the outage are managed by resource `Outage.Handler`.

When you're sure everything is set up, you can announce the outage using
`Outage.Announce`.

When working on the resolution, you can post updates using `Outage.Update`.
`Outage.Update` will change staged outages directly, but for announced outages,
it will just post the changes as updates. Updates can be browsed using the
`OutageUpdate` resource.

When the outage is resolved or cancelled, you can change the state using
`Outage.Close` or `Outage.Cancel`. These actions will create outage updates
as well.

When posting an update or changing state, you can choose whether you want
e-mails sent to affected users or not.
