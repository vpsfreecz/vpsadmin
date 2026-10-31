{
  config,
  lib,
  ...
}:
let
  frontend = config.vpsadmin.frontend;
  webui = config.vpsadmin.webui;
  frontendHosts = lib.optionals frontend.enable (
    lib.concatMap (app: map (instance: instance.virtualHost) (lib.attrValues frontend.${app})) [
      "api"
      "auth"
      "webui"
    ]
  );
  protectedHosts = frontendHosts ++ lib.optional webui.enable webui.domain;

  protectRedirect =
    name: host:
    if !(lib.elem name protectedHosts) || !host.forceSSL then
      host
    else
      let
        serverName = if host.serverName != null then host.serverName else name;
        certName = if host.useACMEHost != null then host.useACMEHost else serverName;
        httpChallenge =
          (host.enableACME || host.useACMEHost != null)
          && config.security.acme.certs.${certName}.dnsProvider == null;
      in
      assert lib.assertMsg (!(host.addSSL || host.onlySSL || host.rejectSSL))
        "services.nginx.virtualHosts.${name}: forceSSL, addSSL, onlySSL and rejectSSL are mutually exclusive";
      host
      // {
        forceSSL = false;
        addSSL = true;
        # nginx's separate forceSSL server omits the host's logging policy.
        # Keep merged listeners and locations in one protected server instead.
        extraConfig = ''
          set $vpsadmin_redirect_scheme $scheme;
          ${lib.optionalString httpChallenge ''
            if ($uri ~ ^/\.well-known/acme-challenge/) {
              set $vpsadmin_redirect_scheme "";
            }
          ''}
          if ($vpsadmin_redirect_scheme = http) {
            return ${toString host.redirectCode} https://$host$request_uri;
          }
        ''
        + host.extraConfig;
      };
in
{
  options.services.nginx.virtualHosts = lib.mkOption {
    apply = lib.mapAttrs protectRedirect;
  };

  config = lib.mkIf (protectedHosts != [ ]) {
    services.nginx.commonHttpConfig = ''
      log_format vpsadmin '$remote_addr [$time_local] "$request_method $uri $server_protocol" $status $body_bytes_sent $request_time $upstream_response_time $upstream_status';
    '';
  };
}
