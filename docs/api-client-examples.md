# API client examples

The API documentation uses HaveAPI's Go and Rust renderers for API 7.0.
Profiles are registered in [the API initialization](../api/lib/vpsadmin/api.rb)
before mounting. Other API versions have no Go or Rust profile. JavaScript,
TypeScript and Python examples use the framework's dynamic clients and do not
need a generated SDK profile.

The Go profile imports `github.com/vpsfreecz/vpsadmin-go-client/client` and
shows the normal `go get ...@latest` installation command. The Rust profile
uses the published [vpsadmin-client](https://crates.io/crates/vpsadmin-client)
crate. Async examples show `cargo add vpsadmin-client`; blocking examples show
`cargo add vpsadmin-client --features blocking`. The profile leaves the SDK
version unspecified. Cargo selects a compatible release using its resolver,
manifest, toolchain and existing lockfile; the server does not resolve a
registry version. SDK versions, API 7.0 and HaveAPI generator versions are
separate identities.

The API bundle must include `haveapi-go-client` and `haveapi-rust-client` at
the same version as `haveapi`. HaveAPI loads the generators during profile
registration and builds their private structural model once at the end of
mounting. Missing generators, incompatible versions and invalid profiles fail
startup. HTML requests use the current user's authorized description and
samples. They do not fetch schemas, generate SDKs or run compilers.

HaveAPI 0.30.2 reuses unchanged, owned context fields when deriving documentation
panels and copies explicitly supplied replacements. Container and string inputs
are detached from caller-owned data, including mutable children of shallow-frozen
containers. Rust examples read the selected action and authentication provider
from the current request's authorized description. Context reuse preserves each
request's authorization and locale; it does not cache pages or authorization
decisions between users. Rendering cost depends on the API shape and must be
measured in the consuming API.

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
An older server cannot read the inline profile configuration. A rollback must
restore the matching configuration and Ruby dependency bundle together.
Mixed workers may show different documentation tabs during an update; this
does not change wire requests, authorization or persisted data. No database
migration or coordinated node update is required by these profiles.
