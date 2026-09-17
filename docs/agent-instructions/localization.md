# Localization and KB impact

Required procedure selected by the repository AGENTS.md. The rules retain their
repository scope and precedence. Paths and commands below are relative to the
repository root unless explicitly stated otherwise.

## Localization

### Knowledge-base documentation impact

Any feature that changes something visible in the WebUI may affect localized
KB navigation text or screenshots. Follow the canonical workflow in
`vpsadmin-kb-captures/docs/webui-change-workflow.md`: pin the vpsAdmin feature
commit there, run its documentation contract, and review every reported Czech
and English page and screenshot concept. A green vpsAdmin test suite alone does
not prove that external documentation remains current.

- Czech translation guidelines are documented in `docs/i18n-cs.md`. Follow the
  terminology there when editing API or WebUI Czech translations.
- API translations are maintained in `api/lib/vpsadmin/api/locales/*.yml` and
  normalized by `rake vpsadmin:i18n:update`.
- vpsAdmin sets HaveAPI `parameter_i18n_scope` to the `vpsadmin` application
  root. Parameter labels/descriptions are generated under
  `vpsadmin.resources`, `vpsadmin.attributes`, and `vpsadmin.meta`; do not add a
  separate `vpsadmin.parameters` tree.
- The locale files include generated key structure from API source and HaveAPI
  parameter metadata. Edit translations in the locale files, then regenerate.
- WebUI runtime translations use gettext domain `vpsAdmin`. Source strings are
  `_()` calls in PHP; the generated source catalog is
  `webui/lang/locale/vpsAdmin.pot`.
- WebUI translations are edited in
  `webui/lang/locale/<locale>/LC_MESSAGES/vpsAdmin.po`; compiled
  `vpsAdmin.mo` files are generated artifacts. Locale maintenance scripts live
  in `webui/lang/scripts/`.
- WebUI language selection uses the browser language for guests, then the
  logged-in user's `User.language` preference. The top-right language switcher
  updates that preference for normal sessions and remains session-only while an
  admin is impersonating another user.
- Keep the standard automated-mail notice uniform in member-facing templates.
  When the notice is present, use these exact visible lines in plain and HTML
  variants; do not paraphrase either language in an individual template:
  - English: `(This is an automated mail from vpsAdmin, your reply will be sent to our support)`
  - Czech: `(Tento mail automaticky rozesílá vpsAdmin, Tvoje odpověď se zašle na naši podporu)`
