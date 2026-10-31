# HTTP logging and OAuth callbacks

The NixOS frontend and WebUI modules protect API, authentication and PHP
request logs by default. Their nginx access records retain client address,
method, normalized path, protocol, status, response size and timings. They
omit queries, request headers, bodies and response headers. Request errors on
these virtual hosts go to `/dev/null` because nginx error messages can include
the original request. Console, download and unrelated nginx hosts keep their
existing logging behavior.

API and authentication frontends replace forwarding headers with the address,
host, scheme and port observed by nginx and discard alternate forwarding
headers. A deployment behind another trusted proxy must configure that trust
explicitly. PHP frontends and the standalone PHP backend send exactly one
`Referrer-Policy: strict-origin` header in the default configuration.

API and PHP HAProxy instances default to `logRequests = false`; the existing
option can override this policy. PHP-FPM keeps native error logging and worker
output capture enabled, with `error_log = syslog` as its default destination.
The PHP application records a fixed category for a failed code-bearing OAuth
callback and retains ordinary native diagnostics outside that callback. These
logging settings leave request values, authentication and sessions unchanged.
TLS and redirect behavior is described below.

## TLS and customization

The private nginx module applies the policy to the fully merged product host
records. A protected host with `forceSSL = true` renders as one host with
`addSSL = true` and an early HTTP-only redirect. This keeps the existing host
key, aliases, default-server identity, certificate settings, listeners and
service locations. The redirect uses the configured `redirectCode` and the
untouched `$host$request_uri`, before Basic authentication or maintenance.
HTTPS retains the normal authentication and service behavior.

When nginx generates an HTTP ACME challenge location, that prefix bypasses
the redirect and keeps nginx's ordinary challenge handling and auth exemption.
DNS challenges receive no exemption. Existing `addSSL`, `onlySSL`, `rejectSSL`
and per-host overrides remain available; mutually exclusive SSL modes remain
invalid.

Explicit listener lists are retained, including lists containing only HTTP or
only TLS listeners. The old two-server `forceSSL` renderer could leave one
server without a listen directive, causing nginx to add an implicit listener.
The protected single-server representation does not synthesize that listener.
Declare both listeners when both are required.

Arbitrary server-level rewrite text can affect exempt HTTP ACME requests, and
custom headers can also apply to HTTP redirects. The module does not interpret
or rewrite such snippets. Operator overrides that restore raw request logging
also override the protection; inspect the final generated configuration after
customization.

## Deployment boundary

Each intermediary needs its own logging policy. Varnish pass-through still
records URLs and headers in its shared-memory log. Route credential-bearing
API/auth traffic directly to HAProxy when using these defaults, or protect
every intermediary separately. Uncontrolled external proxies, errors before
nginx selects a virtual host, and sensitive values embedded in URL paths are
outside this per-host query/header guarantee.

Deploy the public-edge protection before the matching PHP backend policy,
and enable callback traffic once both are in place. Keep protective routing
and logging on rollback.
The defaults do not establish privacy for an existing running deployment;
verify its actual frontend, intermediaries, backend and native log destination.
No database migration or coordinated node update is required.
