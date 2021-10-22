{ vpsadmin-source, vpsadminPath ? <vpsadmin> }:
pkgs:
import "${vpsadmin-source}/webui" { inherit pkgs; }
