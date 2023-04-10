# vpsAdmin
Control panel for managing virtual servers on top of
[vpsAdminOS](https://github.com/vpsfreecz/vpsadminos). This is a monorepo
containing all of vpsAdmin's components: API server, web interface, node control
daemon, NixOS configuration modules, etc.

## Deployment
vpsAdmin is deployed on vpsFree.cz infrastructure as a part of
[vpsfree-cz-configuration](https://github.com/vpsfreecz/vpsfree-cz-configuration).
While this repository contains NixOS modules for all of vpsAdmin components,
there's no documented way of creating a new installation, e.g. configuring the
database, etc.
