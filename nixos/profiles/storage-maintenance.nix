# Import alongside the ordinary vpsAdminOS integration. These final-value
# assertions refuse conflicting workloads; they do not establish physical quiet.
{ config, lib, ... }:
{
  osctld.enable = false;
  runit.services.nodectld.runlevels = [ ];

  assertions = [
    {
      assertion = config.vpsadmin.nodectld.enable;
      message = "storage-maintenance requires vpsadmin.nodectld.enable = true";
    }
    {
      assertion = config.runit.services.nodectld.runlevels == [ ];
      message = "storage-maintenance requires empty nodectld runlevels";
    }
    {
      assertion = !config.osctld.enable;
      message = "storage-maintenance requires osctld.enable = false";
    }
    {
      assertion = config.runit.services.osctld.runlevels == [ ];
      message = "storage-maintenance requires empty osctld runlevels";
    }
    {
      assertion = config.osctl.pools == { };
      message = "storage-maintenance requires empty osctl.pools";
    }
    {
      assertion = !config.osctl.exportfs.enable;
      message = "storage-maintenance requires osctl.exportfs.enable = false";
    }
    {
      assertion = lib.all (pool: !pool.install) (builtins.attrValues config.boot.zfs.pools);
      message = "storage-maintenance requires boot.zfs.pools.<name>.install = false";
    }
    {
      assertion = !config.osctl.oomd.enable;
      message = "storage-maintenance requires osctl.oomd.enable = false";
    }
    {
      assertion = !config.services.prometheus.exporters.osctl.enable;
      message = "storage-maintenance requires the osctl Prometheus exporter to be disabled";
    }
  ];
}
