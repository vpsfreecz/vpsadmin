{
  composerEnv,
  fetchurl,
  fetchgit ? null,
  fetchhg ? null,
  fetchsvn ? null,
  noDev ? false,
}:

let
  packages = {
    "bacon/bacon-qr-code" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "bacon-bacon-qr-code-8674e51bb65af933a5ffaf1c308a660387c35c22";
        src = fetchurl {
          url = "https://api.github.com/repos/Bacon/BaconQrCode/zipball/8674e51bb65af933a5ffaf1c308a660387c35c22";
          sha256 = "0hb0w6m5rwzghw2im3yqn6ly2kvb3jgrv8jwra1lwd0ik6ckrngl";
        };
      };
    };
    "dasprid/enum" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "dasprid-enum-8dfd07c6d2cf31c8da90c53b83c026c7696dda90";
        src = fetchurl {
          url = "https://api.github.com/repos/DASPRiD/Enum/zipball/8dfd07c6d2cf31c8da90c53b83c026c7696dda90";
          sha256 = "1ainxbpfbh9fir2vihc4q614yq6rc3lvz6836nddl50wx2zpcby2";
        };
      };
    };
    "endroid/qr-code" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "endroid-qr-code-aec7fb1f008ed515f0580d7871dffa19428efb82";
        src = fetchurl {
          url = "https://api.github.com/repos/endroid/qr-code/zipball/aec7fb1f008ed515f0580d7871dffa19428efb82";
          sha256 = "1b8ackckk9iadygqhsyjhpfkad8s3dykyf9y5gw2miykbh3hikwq";
        };
      };
    };
    "guzzlehttp/guzzle" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "guzzlehttp-guzzle-7b2f29fe81dc4da0ca0ea7d42107a0845946ea77";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/guzzle/zipball/7b2f29fe81dc4da0ca0ea7d42107a0845946ea77";
          sha256 = "0zmkjb1ryw4k4hm8p8fgj41as6bgxbnhc3lksc5bd90rx6q4xi1q";
        };
      };
    };
    "guzzlehttp/promises" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "guzzlehttp-promises-481557b130ef3790cf82b713667b43030dc9c957";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/promises/zipball/481557b130ef3790cf82b713667b43030dc9c957";
          sha256 = "168fa8nqr7823hc0d65r5lwlc9mq4bm2b4zkwn544nrkp7wvy0sf";
        };
      };
    };
    "guzzlehttp/psr7" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "guzzlehttp-psr7-c2270caaabe631b3b44c85f99e5a04bbb8060d16";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/psr7/zipball/c2270caaabe631b3b44c85f99e5a04bbb8060d16";
          sha256 = "0kmnrz9f8mzf3bd3v3kvq11ii6drbchjck8hgzywkfm8zpfm741f";
        };
      };
    };
    "haveapi/client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "haveapi-client-0bcc032a2a6a529053d999df4593636f74de2576";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/haveapi-client-php/zipball/0bcc032a2a6a529053d999df4593636f74de2576";
          sha256 = "0bby200zd79x7kpppaw2c1153fi6rx3ll72sq5n6n1rh5059qdri";
        };
      };
    };
    "league/oauth2-client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "league-oauth2-client-160d6274b03562ebeb55ed18399281d8118b76c8";
        src = fetchurl {
          url = "https://api.github.com/repos/thephpleague/oauth2-client/zipball/160d6274b03562ebeb55ed18399281d8118b76c8";
          sha256 = "1vyd8c64armlaf9zmpjx2gy0nvv4mhzy5qk9k26k75wa9ffh482s";
        };
      };
    };
    "paragonie/random_compat" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "paragonie-random_compat-996434e5492cb4c3edcb9168db6fbb1359ef965a";
        src = fetchurl {
          url = "https://api.github.com/repos/paragonie/random_compat/zipball/996434e5492cb4c3edcb9168db6fbb1359ef965a";
          sha256 = "0ky7lal59dihf969r1k3pb96ql8zzdc5062jdbg69j6rj0scgkyx";
        };
      };
    };
    "psr/cache" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "psr-cache-aa5030cfa5405eccfdcb1083ce040c2cb8d253bf";
        src = fetchurl {
          url = "https://api.github.com/repos/php-fig/cache/zipball/aa5030cfa5405eccfdcb1083ce040c2cb8d253bf";
          sha256 = "07rnyjwb445sfj30v5ny3gfsgc1m7j7cyvwjgs2cm9slns1k1ml8";
        };
      };
    };
    "psr/http-client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "psr-http-client-bb5906edc1c324c9a05aa0873d40117941e5fa90";
        src = fetchurl {
          url = "https://api.github.com/repos/php-fig/http-client/zipball/bb5906edc1c324c9a05aa0873d40117941e5fa90";
          sha256 = "1dfyjqj1bs2n2zddk8402v6rjq93fq26hwr0rjh53m11wy1wagsx";
        };
      };
    };
    "psr/http-factory" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "psr-http-factory-2b4765fddfe3b508ac62f829e852b1501d3f6e8a";
        src = fetchurl {
          url = "https://api.github.com/repos/php-fig/http-factory/zipball/2b4765fddfe3b508ac62f829e852b1501d3f6e8a";
          sha256 = "1ll0pzm0vd5kn45hhwrlkw2z9nqysqkykynn1bk1a73c5cjrghx3";
        };
      };
    };
    "psr/http-message" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "psr-http-message-402d35bcb92c70c026d1a6a9883f06b2ead23d71";
        src = fetchurl {
          url = "https://api.github.com/repos/php-fig/http-message/zipball/402d35bcb92c70c026d1a6a9883f06b2ead23d71";
          sha256 = "13cnlzrh344n00sgkrp5cgbkr8dznd99c3jfnpl0wg1fdv1x4qfm";
        };
      };
    };
    "ralouphie/getallheaders" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "ralouphie-getallheaders-120b605dfeb996808c31b6477290a714d356e822";
        src = fetchurl {
          url = "https://api.github.com/repos/ralouphie/getallheaders/zipball/120b605dfeb996808c31b6477290a714d356e822";
          sha256 = "1bv7ndkkankrqlr2b4kw7qp3fl0dxi6bp26bnim6dnlhavd6a0gg";
        };
      };
    };
    "symfony/deprecation-contracts" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "symfony-deprecation-contracts-63afe740e99a13ba87ec199bb07bbdee937a5b62";
        src = fetchurl {
          url = "https://api.github.com/repos/symfony/deprecation-contracts/zipball/63afe740e99a13ba87ec199bb07bbdee937a5b62";
          sha256 = "1blzjsmk38b36l15khbx2qs3c6xqmfp32l9xxq3305ifshw7ldby";
        };
      };
    };
    "vpsfreecz/httpful" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "vpsfreecz-httpful-770a0e173e304ebbabf8424ab86a0917bd61622f";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/httpful/zipball/770a0e173e304ebbabf8424ab86a0917bd61622f";
          sha256 = "0h9slrf711sa27dbfgi8q3p9h9iwbxzw6sg3z0f069vy2dy2kyjl";
        };
      };
    };
    "whichbrowser/parser" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "whichbrowser-parser-581d614d686bfbec3529ad60562a5213ac5d8d72";
        src = fetchurl {
          url = "https://api.github.com/repos/WhichBrowser/Parser-PHP/zipball/581d614d686bfbec3529ad60562a5213ac5d8d72";
          sha256 = "010z1ys1hz8hnw0yaj1yv9g0d3krral7k3xk2j3rwwmmic20vwgs";
        };
      };
    };
  };
  devPackages = { };
in
composerEnv.buildPackage {
  inherit packages devPackages noDev;
  name = "vpsadmin-webui";
  src = composerEnv.filterSrc ./.;
  executable = false;
  symlinkDependencies = false;
  meta = { };
}
