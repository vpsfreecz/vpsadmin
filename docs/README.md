# vpsAdmin documentation

These pages describe vpsAdmin for developers and operators. Start with the
[architecture overview](overview.md).

## Topics

- [Transactions](transactions.md): node commands, chains, resource locks, and
  database confirmations.
- [Object lifetimes](object-lifetimes.md): suspension, deletion, expiration,
  and state transitions.
- [Plugins](plugins.md): API extensions, loading, and database migrations.
- [Storage](storage/README.md): datasets, pools, snapshots, and operations.
  - [Backup branching](storage/branching.md)
  - [Snapshot downloads and local backups](storage/download.md)
- [Czech translation conventions](i18n-cs.md)

For member guides, see the [Czech knowledge base](https://kb.vpsfree.cz/) or
[English knowledge base](https://kb.vpsfree.org/). Deployment details specific
to vpsFree.cz belong in
[vpsfree-cz-configuration](https://github.com/vpsfreecz/vpsfree-cz-configuration).
Development commands, verification and localization procedures are required by
the routing table in [AGENTS.md](../AGENTS.md).

## Writing documentation

Write ordinary Markdown files here and link them from this index. The files
are meant to be read in a checkout or on GitHub; reading and editing them
requires no documentation build. A site generator can be added if publishing
becomes useful.

Use one descriptive title per page, fenced code blocks with a language where
appropriate, and relative links to the actual `.md` files. Use lowercase
filenames with hyphens. Keep related pages together and add directories when
a topic needs several pages.

Describe supported behavior and check examples against the code. Explain the
reason for consequential design choices and link relevant source files. When
a change needs deployment ordering or recovery steps, document those with the
component that owns the procedure. Update the explanation with the code.

Keep pages useful on their own. Link to existing explanations instead of
copying them, and remove obsolete instructions when they no longer apply.
