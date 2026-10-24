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

HaveAPI 0.31.2 reuses unchanged, owned context fields when deriving documentation
panels and copies explicitly supplied replacements. Container and string inputs
are detached from caller-owned data, including mutable children of shallow-frozen
containers. Generated examples read the selected action and authentication
provider from the current request's authorized description. Context reuse
preserves each request's authorization and locale; it does not cache pages or
authorization decisions between users. Rendering cost depends on the API shape
and must be measured in the consuming API.

## Generated and dynamic TypeScript

The generated SDK supplies vpsAdmin-specific resource, action, input and result
types from a saved API schema. The generic `haveapi-client` callback and async
clients discover resources dynamically; their TypeScript declarations describe
the generic client API. Generated calls use the generic async runtime for
transport and authentication. Server authorization and validation still apply.

The published generated SDK 0.1.1 requires `haveapi-client@0.30.2`, and HaveAPI
0.31.2's TypeScript renderer emits that supported runtime version. Install this
pair in an example consumer:

```sh
npm install vpsadmin-typescript-client@0.1.1 haveapi-client@0.30.2
```

These example dependencies are separate from vpsAdmin's HaveAPI 0.31.2 application
dependencies. Generated programs use an API base ending in `/v7.0` without the
runtime constructor's `version` option. The profile supplies only
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
