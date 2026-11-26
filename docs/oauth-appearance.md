# OAuth appearance and branding

The OAuth sign-in and password recovery pages offer light, dark and automatic
appearance. Automatic follows the browser's system preference, including changes
while a page is open. The compact appearance controls support keyboard navigation
and have text labels for assistive technology.

A valid incoming `theme=light|dark|auto` takes precedence over the browser's saved
choice. Opening a link does not save that incoming value. Choosing an appearance
on the page saves it locally under `vpsadmin.oauth.appearance.v1`; only the enum
is stored. When storage is unavailable, forms and recovery navigation retain the
choice for the current flow. With JavaScript disabled, an explicit request theme
still works and automatic appearance follows the system through CSS.

## OAuth clients

Clients that implement the [HaveAPI theme extension](https://github.com/vpsfreecz/haveapi/blob/master/doc/en/oauth-theme.md)
send `theme_return=1` separately from the initial `theme`. Successful authorization
then returns the current preference as `theme`. The separate opt-in preserves
clients that reject unknown callback fields. Changing appearance on the provider
does not opt a client into this extension.

Clients must validate OAuth state and successfully exchange the authorization
code before applying a returned theme. Cancellation and failed authentication
retain the client's initiating preference. Theme values carry no authentication
authority and never replace state, PKCE, redirect validation, scopes or tokens.
An older provider can ignore the extension; the client keeps its initiating
preference when no valid theme is returned.

Password recovery has its own browser flow. Its same-origin forms and links
retain appearance, but returning to a service uses the registered
`authorization_start_uri` unchanged and begins a fresh login. Recovery emails and
tokens do not carry theme values. A link opened in another browser uses that
browser's saved choice or automatic appearance.

## Deployment branding

Configure public image files with the NixOS module:

```nix
vpsadmin.authentication = {
  logo = ./logo.png;
  lightLogo = ./logo-light.png;
  darkLogo = ./logo-dark.png;
};
```

All three options default to `null`. Each accepts a file path. The module copies
readable regular files into the immutable system closure and checks the suffix:
PNG, JPEG (`.jpg` or `.jpeg`), WebP or SVG. It does not fetch URLs or convert
images. All API hosts need the same configuration when they serve one origin.

For each scheme, the specific file takes precedence over the common `logo`.
Without a usable configured file, the page uses the bundled inline vpsAdmin
wordmark. Images retain their aspect ratios in the header. Passkey registration
uses only the light variant and does not participate in theme selection.

The module generates `authentication.logo_file`, `light_logo_file` and
`dark_logo_file` in `deployment.json`, preserving unrelated configuration. These
keys are reserved: do not set them through `vpsadmin.deploymentConfig`, even to
the same value. Non-Nix installations can supply those keys directly with
trusted absolute local file paths. Empty, unavailable or unsupported direct JSON
values fall through to the next candidate. The configuration is cached; restart
API workers after changing it.

The API serves configured images at the finite same-origin paths
`/_auth/appearance/logo/light` and `/_auth/appearance/logo/dark`. GET and HEAD
use explicit image MIME types, inline disposition, `nosniff`, content-derived
ETags and `public, max-age=0, must-revalidate` caching. Conditional requests
return 304 without a body. Unknown or unavailable images return 404; query
parameters cannot select files. No response exposes a local path. The existing
`/_auth` frontend proxy covers both routes, so site nginx aliases are unnecessary.
Recovery's image CSP remains restricted to its own origin.

SVG artwork must be trusted and self-contained. Inline style blocks, style
attributes, system fonts and internal references are supported. Image responses
use `default-src 'none'; style-src 'unsafe-inline'; sandbox; base-uri 'none';
form-action 'none'` to block scripts and external resources. Interactive SVG and
hyperlinks are unsupported; the CSP is not an SVG sanitizer or a guarantee
against every direct-link navigation. The API does not sanitize or convert files.

The API neither reads nor registers `core.logo_url`. Existing rows remain
untouched. Installations that used only that setting must configure file-based
branding or use the bundled wordmark. No database migration or node update is
needed.

## Dependency readiness and rollout

Production packages, ordinary development shells and normal CI use released
HaveAPI dependencies. Before enabling theme exchange in production, select a
HaveAPI release containing the theme response hook and documentation theme
support. Generator profiles explicitly require the released Go, Rust and
TypeScript generators at 0.32.2, independently of the server version.

Source-backed development checks use an explicitly selected separate bundle.
These checks verify unreleased behavior; they do not verify a released artifact.
Only the two returned-theme route examples are pending on released HaveAPI
0.32.2 when its base response hook is absent. Their assertions remain intact;
another dependency version without the hook fails. Compatible-source checks
execute both examples without pending status. Ordinary authentication, opt-out
and fallback checks continue in release mode.

Deploy the asset closures and matching API to all workers before relying on the
new logo routes. Mixed old and new workers can produce missing images while
ordinary authentication continues. Older modules do not accept the new options.
Rollback restores the matching previous API and configuration generation,
including its branding arrangement. Appearance rollback needs no schema
conversion or authenticated-session revocation.
