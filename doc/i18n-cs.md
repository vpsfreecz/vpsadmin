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
- `Kernel` is `Jádro`.
- `Monitoring` is `Monitoring`.
- `Storage` is `Úložiště`.
- `Location`/`Locations` are `Lokace`.
- A planned outage is `odstávka`; an unplanned outage is `výpadek`.
  Never use `plánovaný výpadek`, `neplánovaný výpadek`,
  `plánované výpadky`, or `neplánované výpadky`.
  In combined outage lists, use labels such as `Odstávky`, `Výpadky`, and
  `Odstávky a výpadky`.
- `Network`/`Networks` are `Síť`/`Sítě`.
- `Export`/`Exports` are `Export`/`Exporty`.
- `Back` navigation links are `Zpět`.
- User-session objects are `relace`, e.g. `uživatelská relace`,
  `relace uživatele`, and `Relace` in menus/headings. Use
  `ukončit relaci` for ending a session, never `zavřít sezení`.
- In user-facing automatic logout messages, describe the event as
  `odhlášení` or `ukončené přihlášení`, e.g. `Přihlášení bylo ukončeno` and
  `Byli jste odhlášeni z důvodu neaktivity`.
- `User data` stays `User data`.
- `Event log` is usually `Události`.
- `Incident reports` are `Incidenty`.
- `DNS resolvers` are `DNS resolvery`.
- `Transfer logs` are `Log přenosů`.
- Network and DNS transfers are `Přenosy`, never `Převody`.
- `Routed addresses` and `Routable addresses` are `Routované adresy`.
- `DNS record log` is `Log DNS záznamů`.
- `Forward zone` in DNS is `Dopředná zóna`, not `Přední zóna`.
- `Logout` button text is `Odhlásit`.
- `Transaction log` stays as English source text; Czech menu text is
  `Transakce`.
- Transaction chain pages can use concise Czech labels such as `Transakce`;
  `Concerns` means affected objects and is translated as `Týká se`, never
  `Obavy`.
- Transaction chain action labels and affected-object labels are translated in
  the API locale files, because both API clients and the WebUI display them.
  The WebUI must not maintain separate PHP-only or JavaScript-only translations
  for these labels.
- Transaction labels are translated in the API locale files and rendered by
  the WebUI from the API-provided `label` field.
- Transaction labels use concise noun/process labels, usually verbal nouns
  such as `Přidání`, `Vytvoření`, `Smazání`, and `Nastavení`, or established
  technical nouns such as `Reload DNS serveru`. Do not use infinitive command
  labels such as `Přidat DNS server` for transaction labels.
- Route and host IP address add/remove transaction labels are intentional
  compact exceptions: use paired labels such as `Přidat routu` and
  `Odebrat routu`.
- `Security advisory` is `Bezpečnostní upozornění`.
- Security advisory `mitigated` state is `ošetřeno`, not a literal
  `zmírněno`.
- SSH/user key `Fingerprint` in short table and field labels is `Otisk`.
  In prose, use `otisk klíče`, `otisk klíče SSH`, or
  `otisk hostitelského klíče SSH` when the type of key needs to be explicit.
- `Dataset`/`Datasets` are `Dataset`/`Datasety`.
- Dataset branches are `větev datasetu`, never `branch datasetu`.
- ZFS dataset property labels use a natural Czech label followed by the exact
  property key in parentheses, e.g. `Využitý prostor (used)` and
  `Referencovaný prostor (referenced)`.
- For ZFS quotas, make the scope clear: `quota` includes descendants, while
  `refquota` applies to the dataset itself. Use labels such as
  `Kvóta včetně potomků (quota)` and `Kvóta datasetu (refquota)`.
- `Mount`/`Mounts` are `Mount`/`Mounty`.
- In mount-related states and errors, use `mount`, e.g. `Selhání při mountu`.
- For an NFS export value in the `host:path` form, use `Adresa exportu`.
  Use `mountpoint` only for the local mount target.
- `Rescue mode` is `nouzový režim`.
- VPS power state `stopped` is `vypnuto`; counts and labels use
  `vypnuté VPS` and summaries use `vypnuto`.
- VPS action `Shutdown` is `Vypnout`. It requests a graceful shutdown inside
  the VPS.
- VPS action `Poweroff` is `Vynutit vypnutí`. It immediately powers off the
  VPS without waiting for the system to shut down.
- Internal API action names such as `stop` and `force_stop` are identifiers and
  remain unchanged, but user-visible labels must use `Shutdown`/`Poweroff` and
  `Vypnout`/`Vynutit vypnutí`.
- Remote console action labels are `Vypnout`, `Restartovat`, `Resetovat`,
  `Vynutit vypnutí`, and `Spustit`.
- `Hostname`, `Loadavg`, `Uptime`, and `User data` are left untranslated.
- VPS `feature`/`features` are `funkce`, for example `Funkce VPS` or
  `Funkce`. Do not use `vlastnosti` for VPS features. Dataset and ZFS
  properties remain `vlastnost`/`vlastnosti`.

Keep established technical terms untranslated when natural:

- API, DNS, VPS, NAS, IPv4, IPv6, FQDN, MAC
- ARC, scrub, resilver, snapshot, dataset, namespace
- mountpoint, resolver, token, login, hostname

Use capitalization that matches the UI context. Main menu and sidebar labels
should start with an uppercase letter. Short table labels should be concise.
Longer descriptions may use full Czech sentences.

Action labels should use the infinitive form, e.g. `Spravovat`, `Vytvořit`,
`Upravit`, and `Vypnout`, not polite imperative forms such as `Spravujte`.

When updating translations:

- vpsAdmin API strings live in `api/lib/vpsadmin/api/locales/*.yml`; edit the
  locale files and run `rake vpsadmin:i18n:update`.
- WebUI gettext strings live in
  `webui/lang/locale/<locale>/LC_MESSAGES/vpsAdmin.po`; edit the `.po` file
  and run `webui/lang/scripts/locales-update`.
- If a visible WebUI string is missing from the catalog, wrap it in `_()` in
  PHP source first, then regenerate the catalog.
