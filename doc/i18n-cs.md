# Czech Translation Guidelines

vpsAdmin is a control panel for virtual server infrastructure. Czech
translations are written for server administrators, developers, and other IT
staff. Prefer natural technical Czech and keep English terms when translating
them would sound forced or change the meaning.

Always translate with context. The same English word can mean different things:

- `Status` is `Status`.
- `State` is `Stav`.
- Disk or resource `free` is `volné` or `volno`, never `zdarma`.
- `Node`/`Nodes` are `Node`/`Nody`, not `uzel`.
- `Cluster` is `Cluster`, not `klastr`.
- `Kernel` is `Kernel`.
- `Monitoring` is `Monitoring`.
- `Storage` is `Úložiště`.
- `Location`/`Locations` are `Lokace`.
- A planned outage is `odstávka`; an unplanned outage is `výpadek`.
  Never use `plánovaný výpadek`.
- `Network`/`Networks` are `Síť`/`Sítě`.
- `Export`/`Exports` are `Export`/`Exporty`.
- `Back` navigation links are `Zpět`.
- `User sessions` are `Sezení`.
- `User data` stays `User data`.
- `Event log` is usually `Události`.
- `Incident reports` are `Incidenty`.
- `DNS resolvers` are `DNS resolvery`.
- `Transfer logs` are `Log přenosů`.
- `DNS record log` is `Log DNS záznamů`.
- `Logout` button text is `Odhlásit`.
- `Transaction log` stays as English source text; Czech menu text is
  `Transakce`.
- `Dataset`/`Datasets` are `Dataset`/`Datasety`.
- `Mount`/`Mounts` are `Mount`/`Mounty`.
- `Hostname`, `Loadavg`, `Uptime`, `Kernel`, and `User data` are left
  untranslated.

Keep established technical terms untranslated when natural:

- API, DNS, VPS, NAS, IPv4, IPv6, FQDN, MAC
- ARC, scrub, resilver, snapshot, dataset, namespace
- mountpoint, resolver, token, login, hostname

Use capitalization that matches the UI context. Main menu and sidebar labels
should start with an uppercase letter. Short table labels should be concise.
Longer descriptions may use full Czech sentences.

When updating translations:

- vpsAdmin API strings live in `api/lib/vpsadmin/api/locales/*.yml`; edit the
  locale files and run `rake vpsadmin:i18n:update`.
- WebUI gettext strings live in
  `webui/lang/locale/<locale>/LC_MESSAGES/vpsAdmin.po`; edit the `.po` file
  and run `webui/lang/scripts/locales-update`.
- If a visible WebUI string is missing from the catalog, wrap it in `_()` in
  PHP source first, then regenerate the catalog.
