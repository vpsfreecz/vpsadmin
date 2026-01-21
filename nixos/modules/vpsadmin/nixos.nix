{
  config,
  lib,
  ...
}:
let
  cfg = config.vpsadmin;
in
{
  services.nginx.appendConfig = lib.mkIf (cfg.frontend.enable || cfg.webui.enable) ''
    worker_processes auto;
  '';
}
