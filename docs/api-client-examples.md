# API client examples

The API documentation uses HaveAPI's Go, Rust and generated TypeScript renderers
for API 7.0. Profiles are registered in
[the API initialization](../api/lib/vpsadmin/api.rb) before mounting. Other API
versions have no generated SDK profiles. JavaScript, dynamic TypeScript and
Python examples remain available without those profiles.

The Go profile imports `github.com/vpsfreecz/vpsadmin-go-client/client` and
shows `go get ...@latest`. The Rust profile uses the published
[vpsadmin-client](https://crates.io/crates/vpsadmin-client) crate. Async examples
show `cargo add vpsadmin-client`; blocking examples show
`cargo add vpsadmin-client --features blocking`. The TypeScript profile uses
[vpsadmin-typescript-client](https://www.npmjs.com/package/vpsadmin-typescript-client)
and its public `createClient` export. Profiles leave SDK versions unspecified;
the user's package manager selects a release. The server does not resolve
registry versions. SDK versions, API 7.0 and HaveAPI generator versions are
separate identities.

The API bundle includes `haveapi-go-client`, `haveapi-rust-client` and
`haveapi-typescript-client` at the same version as `haveapi`. HaveAPI loads the
generators during profile registration and builds their private structural
models at the end of mounting. Missing generators, incompatible versions and
invalid profiles fail startup. HTML requests use the current user's authorized
description and samples. They do not fetch schemas, generate SDKs or run
compilers.

The selected HaveAPI source reuses unchanged, owned context fields when deriving
documentation panels and copies explicitly supplied replacements. Container and string inputs
are detached from caller-owned data, including mutable children of shallow-frozen
containers. Generated examples read the selected action and authentication
provider from the current request's authorized description. Context reuse
preserves each request's authorization and locale; it does not cache pages or
authorization decisions between users. Rendering cost depends on the API shape
and must be measured in the consuming API.

## Documentation navigation and identity

Open `/v7.0/` for initialization examples, `?page=authentication` for API
credential examples, `?page=resources` for the directory, or `?resource=node`
for a resource and its own actions. Nested resources use dotted paths.
Slashless known version GET/HEAD URLs redirect to their slash form with the
query preserved. `/doc` and its index/readme aliases display the packaged
HaveAPI README. Internal guides remain neutral and do not sign readers in.

HTML documentation and its search index use only a valid documentation OAuth
cookie. Basic, Bearer, custom token headers and query credentials neither select
that identity nor override it. Without a valid cookie, including when OAuth is
unconfigured, documentation lists all declared resources anonymously. With a
valid cookie, the requested API version validates its access token through the
normal OAuth policy, then filters the page and search results for that account.
Explicit language headers retain their negotiated locale. An invalid or expired
session returns to the anonymous view.

Ordinary API requests, JSON and OPTIONS descriptions, mutations and provider
endpoints retain their existing credential handling. A documentation cookie
does not authenticate them. Legacy documentation `_login` and `_logout`
GET/HEAD links redirect to the default overview without challenging, signing
out or clearing a session. Use Documentation settings for OAuth sign-in,
sign-out, optional Switch user and theme choices.

## Released gem packaging and documentation sign-in

The API server and four Ruby client/generator gems use the same HaveAPI release
series from RubyGems. The released server gem includes its generated
README, internal guides, JSON schema and documentation assets. Check the
installed documentation contents and all five loaded gem paths when updating
the bundle. A successful Ruby require alone does not prove that the assets were
packaged. The PHP and browser JavaScript clients use their own released
packages; external SDK dependencies remain separate.

Use the existing configure-before-mount hook for documentation sign-in. Copy
[`api/config/api.rb.example`](../api/config/api.rb.example) to the API's private
`config/api.rb` as a regular file. The NixOS API setup preserves regular private
configuration files. The sample sets the documentation label from the configured
API URL's host and reads these adjacent private files:

- `documentation-oauth.json`: an object with `client_id`, `client_secret` and
  `redirect_uri` strings, plus optional boolean `switch_user` (default `false`).
- `documentation-session.key`: at least 64 bytes of stable random secret material,
  shared by all API workers.

Keep both files outside Git and the Nix store, readable only by their owner and
the API service as required. A missing OAuth JSON file leaves the optional
client disabled. Malformed JSON, missing fields, an invalid option or a missing
session key fails startup. The sample suppresses parsed values and nested
validation errors in its configuration diagnostic.

Register a dedicated nondefault confidential OAuth client through the ordinary
API. Use fixed 3600-second access tokens, no refresh tokens, and
`allow_single_sign_on: false`. Set its exact HTTPS redirect to
`<API origin>/_documentation/oauth/callback`; the API is mounted at `/`.
The sample requests scope `['all']` and limits its documentation session to
3600 seconds. Keep `switch_user` disabled until a fresh authorization with this
client offers editable account credentials. Do not reuse PHP or React client
credentials.

HaveAPI obtains authorize, token and revoke URLs from the default API version's
OAuth provider metadata. vpsAdmin derives those URLs from `core.auth_url`, or
`core.api_url` when no separate authentication URL is configured. They use
`/_auth/oauth2/` without an API-version prefix. Both the browser and API workers
must trust the provider's HTTPS certificate. Keep sufficient worker concurrency
for same-origin token and revoke requests.

The test/development nginx frontend replaces client-supplied forwarding metadata
with its own scheme, host, port and remote address. Its API/auth access log omits
queries and its API/auth error log is disabled because nginx error messages can
include the original request. The whole API virtual host connects directly to
HAProxy, whose API request logging is disabled. It bypasses Varnish because
Varnish shared-memory logging can retain request and response values even for
uncached requests. This also removes the test/development API metrics endpoint's
60-second Varnish cache. Keep the direct route on rollback while documentation
OAuth remains enabled. Retain these settings when exposing documentation OAuth
callbacks; never capture callback queries, credentials, cookies or tokens in
request logs.

The isolated [schema exporter](api-schema-export.md) pins HaveAPI 0.32.0 for
reproducible schema exports. Deploy or roll back the private documentation
configuration together with its matching API bundle; older documentation code
cannot load these options. OAuth client administration remains a separate
operation.

## Generated and dynamic TypeScript

The generated SDK supplies vpsAdmin-specific resource, action, input and result
types from a saved API schema. The generic `haveapi-client` callback and async
clients discover resources dynamically; their TypeScript declarations describe
the generic client API. Generated calls use the generic async runtime for
transport and authentication. Server authorization and validation still apply.

The published generated SDK 0.1.1 requires `haveapi-client@0.30.2`. Install this
pair in an example consumer:

```sh
npm install vpsadmin-typescript-client@0.1.1 haveapi-client@0.30.2
```

These example dependencies are separate from vpsAdmin's Ruby application
dependencies. Generated programs use an API base ending in `/v7.0`
without the runtime constructor's `version` option. The profile supplies only
`package_name: 'vpsadmin-typescript-client'`; it uses the mounted model and
omits a saved snapshot and SDK version override.

## SDK compatibility

A package name does not prove that a generated SDK matches the current API.
When changing resources, routes or parameter types, compare the rendered
imports, action members, path arguments, setters and response fields against
the selected SDK. Compile complete emitted programs against that SDK in a
disposable consumer. Do not regenerate an SDK inside a documentation request.
Samples that the renderer cannot represent show a limitation.

The focused spec in
[`api/spec/lib/vpsadmin/api/documentation_clients_spec.rb`](../api/spec/lib/vpsadmin/api/documentation_clients_spec.rb)
checks the mounted vpsAdmin profiles, emitted programs and request-local
authorization. The `services-up` integration test checks the same tabs through
the packaged API, including the optional generator gems and documentation
assets. Compilation against external SDKs is a separate check.

## Upgrade and rollback

Deploy profile configuration, generator gems and the HaveAPI server together.
An older server cannot read the generated TypeScript profile configuration.
A rollback must restore the matching configuration and Ruby dependency bundle
together. Mixed workers may show different documentation tabs during an update;
this does not change wire requests, authorization or persisted data. No database
migration or coordinated node update is required by these profiles.
