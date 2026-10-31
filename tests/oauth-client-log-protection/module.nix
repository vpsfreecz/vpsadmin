# Evaluate with the repository's locked nixpkgs; no service VM or build is needed.
{ nixpkgs }:
let
  lib = nixpkgs.lib;
  selectHost =
    host:
    lib.getAttrs [
      "serverName"
      "serverAliases"
      "default"
      "listen"
      "listenAddresses"
      "forceSSL"
      "addSSL"
      "onlySSL"
      "rejectSSL"
      "redirectCode"
      "enableACME"
      "useACMEHost"
      "acmeRoot"
      "extraConfig"
    ] host;
  evaluate =
    extra:
    (lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ../../nixos/modules/nixos-modules.nix
        ({ lib, ... }: {
          system.stateVersion = "26.05";
          time.timeZone = "UTC";
          vpsadmin.enableOverlay = lib.mkForce false;
          vpsadmin.frontend = {
            enable = true;
            api.test = {
              domain = "api.test";
              aliases = [ "alias.test" ];
              backend = {
                host = "127.0.0.1";
                port = 18081;
              };
            };
            auth.test = {
              domain = "auth.test";
              backend = {
                host = "127.0.0.1";
                port = 18081;
              };
            };
            webui.test = {
              domain = "webui.test";
              backend = {
                host = "127.0.0.1";
                port = 18081;
              };
            };
            console-router.test = {
              domain = "console.test";
              backend = {
                host = "127.0.0.1";
                port = 18081;
              };
            };
          };
          vpsadmin.webui = {
            enable = true;
            domain = "php.test";
            package = "/fixture/webui";
            api.externalUrl = "https://api.test";
            api.internalUrl = "https://api.test";
            productionEnvironmentId = 1;
          };
          vpsadmin.haproxy = {
            enable = true;
            api.test = {
              frontend.bind = [ "127.0.0.1:15000" ];
              backends = [
                {
                  host = "127.0.0.1";
                  port = 9292;
                }
              ];
            };
            webui.test = {
              frontend.bind = [ "127.0.0.1:15001" ];
              backends = [
                {
                  host = "127.0.0.1";
                  port = 80;
                }
              ];
            };
            console-router.test = {
              frontend.bind = [ "127.0.0.1:15002" ];
              backends = [
                {
                  host = "127.0.0.1";
                  port = 8000;
                }
              ];
            };
          };
          services.nginx = {
            enableReload = true;
            validateConfigFile = false; # Read generated text, validated by native fixture.
            # Isolate nginx's otherwise compiled-in default access-log destination.
            commonHttpConfig = "access_log /fixture/logs/access.log;";
            defaultListenAddresses = [ "127.0.0.1" ];
            defaultHTTPListenPort = 18080;
            defaultSSLListenPort = 18443;
            recommendedTlsSettings = lib.mkForce false;
            virtualHosts = {
              "api.test".default = true;
              "unrelated.test".locations."/".return = "204";
            };
          };
        })
        extra
      ];
    }).config;
  summarize =
    extra:
    let
      c = evaluate extra;
    in
    {
      hosts = lib.mapAttrs (_: selectHost) c.services.nginx.virtualHosts;
      nginxConfig = c.environment.etc."nginx/nginx.conf".source.text;
      nginx = "${c.services.nginx.package}/bin/nginx";
      poolSettings = c.services.phpfpm.pools.vpsadmin-webui.settings;
      haproxy = c.services.haproxy.config;
    };
  ssl = {
    sslCertificate = "/fixture/cert.pem";
    sslCertificateKey = "/fixture/key.pem";
  };
  hostCase = host: { services.nginx.virtualHosts."api.test" = ssl // host; };
  runtime = summarize (
    { lib, ... }: {
      vpsadmin.frontend.api.maintenance = {
        domain = "maintenance.test";
        maintenance.enable = true;
        backend = {
          host = "127.0.0.1";
          port = 18081;
        };
      };
      services.nginx.virtualHosts =
        lib.genAttrs [ "api.test" "auth.test" "webui.test" "php.test" "maintenance.test" ] (
          name:
          ssl
          // {
            forceSSL = lib.mkForce true;
            redirectCode = 308;
            basicAuthFile = "/fixture/htpasswd";
          }
        )
        // {
          "api.test" = ssl // {
            forceSSL = lib.mkForce true;
            redirectCode = 308;
            basicAuthFile = "/fixture/htpasswd";
            enableACME = true;
            acmeRoot = "/fixture/acme";
          };
        };
      security.acme = {
        acceptTerms = true;
        defaults.email = "test@example.invalid";
      };
    }
  );
in
{
  inherit runtime;
  cases = {
    plain = summarize { };
    addSSL = summarize (hostCase {
      addSSL = true;
    });
    onlySSL = summarize (hostCase {
      onlySSL = true;
    });
    rejectSSL = summarize (hostCase {
      rejectSSL = true;
    });
    forceSSL = summarize (hostCase {
      forceSSL = true;
    });
    overrideGlobal = summarize (
      { lib, ... }: {
        vpsadmin.frontend.forceSSL = true;
        services.nginx.virtualHosts = {
          "api.test".forceSSL = lib.mkForce false;
          "auth.test" = ssl;
          "webui.test" = ssl;
          "console.test" = ssl;
        };
      }
    );
    customListeners = summarize (hostCase {
      forceSSL = true;
      redirectCode = 307;
      listenAddresses = [
        "127.0.0.2"
        "[::1]"
      ];
    });
    explicitListeners = summarize (hostCase {
      forceSSL = true;
      listen = [
        {
          addr = "127.0.0.2";
          port = 18082;
          ssl = false;
        }
        {
          addr = "[::1]";
          port = 18445;
          ssl = true;
        }
      ];
    });
    httpOnlyList = summarize (hostCase {
      forceSSL = true;
      listen = [
        {
          addr = "127.0.0.2";
          port = 18082;
          ssl = false;
        }
      ];
    });
    tlsOnlyList = summarize (hostCase {
      forceSSL = true;
      listen = [
        {
          addr = "127.0.0.2";
          port = 18445;
          ssl = true;
        }
      ];
    });
    sharedHttpAcme = summarize {
      services.nginx.virtualHosts."api.test" = {
        forceSSL = true;
        useACMEHost = "shared.test";
      };
      security.acme.certs."shared.test" = {
        email = "test@example.invalid";
        webroot = "/fixture/acme";
      };
    };
    dnsAcme = summarize {
      services.nginx.virtualHosts."api.test" = {
        forceSSL = true;
        enableACME = true;
      };
      security.acme.certs."api.test" = {
        email = "test@example.invalid";
        dnsProvider = "fixture";
      };
    };
  };
  invalid = lib.genAttrs [ "addSSL" "onlySSL" "rejectSSL" ] (
    mode:
    !(builtins.tryEval (
      builtins.deepSeq
        (evaluate (hostCase {
          forceSSL = true;
          ${mode} = true;
        })).services.nginx.virtualHosts."api.test"
        true
    )).success
  );
}
