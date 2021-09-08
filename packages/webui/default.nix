{ vpsadminPath ? <vpsadmin> }:
pkgs:
import "${vpsadminPath}/webui" { inherit pkgs; }
