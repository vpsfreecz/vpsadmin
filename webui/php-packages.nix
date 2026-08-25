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
        name = "dasprid-enum-b5874fa9ed0043116c72162ec7f4fb50e02e7cce";
        src = fetchurl {
          url = "https://api.github.com/repos/DASPRiD/Enum/zipball/b5874fa9ed0043116c72162ec7f4fb50e02e7cce";
          sha256 = "1b6l6974c5s1f4bz380z93hirf3arypy7yljafifbp4359ainb0x";
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
        name = "guzzlehttp-guzzle-ee80339fd9177ba44c49cdb653ff02a4d1106b9a";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/guzzle/zipball/ee80339fd9177ba44c49cdb653ff02a4d1106b9a";
          sha256 = "0bjpx0m9yaw87d0kxqp59w4ijf73qc6dw4if74jihxq5cpj0sa29";
        };
      };
    };
    "guzzlehttp/promises" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "guzzlehttp-promises-cde49999552d185d64715fe9c1f77a2aadd2f9f1";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/promises/zipball/cde49999552d185d64715fe9c1f77a2aadd2f9f1";
          sha256 = "0csxia10vlbhlf77lj188pc62cijfq5nk6rjrpx3hcmb3x5cmxfj";
        };
      };
    };
    "guzzlehttp/psr7" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "guzzlehttp-psr7-95e7828100de18b4e269fb1703be530082d5166d";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/psr7/zipball/95e7828100de18b4e269fb1703be530082d5166d";
          sha256 = "086ww2zb1b5p6lsiz0ibqa105bzi39jkxkm30jb2h46s684z2g1x";
        };
      };
    };
    "haveapi/client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "haveapi-client-27da6934f0497501187f77d14b566469dd4a7e14";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/haveapi-client-php/zipball/27da6934f0497501187f77d14b566469dd4a7e14";
          sha256 = "0bs2ppdmbixw65wkkqmqq1p9ajygrh05jsyy6wzwdiazi9njn281";
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
        name = "symfony-deprecation-contracts-f3202fa1b5097b0af062dc978b32ecf63404e31d";
        src = fetchurl {
          url = "https://api.github.com/repos/symfony/deprecation-contracts/zipball/f3202fa1b5097b0af062dc978b32ecf63404e31d";
          sha256 = "0zb8z5rslxgqd548hhy6svpw6pqmc0lqx4540sa5fkxa1434349x";
        };
      };
    };
    "symfony/polyfill-php80" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "symfony-polyfill-php80-dfb55726c3a76ea3b6459fcfda1ec2d80a682411";
        src = fetchurl {
          url = "https://api.github.com/repos/symfony/polyfill-php80/zipball/dfb55726c3a76ea3b6459fcfda1ec2d80a682411";
          sha256 = "0vhq5kidlw4n00msiisnhqnyw80g4qlfap1mkh4bvdp08izf7r36";
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
  devPackages = {
    "myclabs/deep-copy" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "myclabs-deep-copy-8680aa248f8e07bc8fb43f56f0f5fc77a0c96aae";
        src = fetchurl {
          url = "https://api.github.com/repos/myclabs/DeepCopy/zipball/8680aa248f8e07bc8fb43f56f0f5fc77a0c96aae";
          sha256 = "1033kq4aip379m7vn8115lrfzzzy5mqjdk0z60c5ihca1pzmrgan";
        };
      };
    };
    "nikic/php-parser" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "nikic-php-parser-044a6a392ff8ad0d61f14370a5fbbd0a0107152f";
        src = fetchurl {
          url = "https://api.github.com/repos/nikic/PHP-Parser/zipball/044a6a392ff8ad0d61f14370a5fbbd0a0107152f";
          sha256 = "1bxr2q8xvlj2195m38bis72fymmnz0x6diikgh6pbzf71zyrp599";
        };
      };
    };
    "phar-io/manifest" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phar-io-manifest-54750ef60c58e43759730615a392c31c80e23176";
        src = fetchurl {
          url = "https://api.github.com/repos/phar-io/manifest/zipball/54750ef60c58e43759730615a392c31c80e23176";
          sha256 = "0xas0i7jd6w4hknfmbwdswpzngblm3d884hy3rba0q2cs928ndml";
        };
      };
    };
    "phar-io/version" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phar-io-version-4f7fd7836c6f332bb2933569e566a0d6c4cbed74";
        src = fetchurl {
          url = "https://api.github.com/repos/phar-io/version/zipball/4f7fd7836c6f332bb2933569e566a0d6c4cbed74";
          sha256 = "0mdbzh1y0m2vvpf54vw7ckcbcf1yfhivwxgc9j9rbb7yifmlyvsg";
        };
      };
    };
    "phpunit/php-code-coverage" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phpunit-php-code-coverage-6ce313bb110384148d1dc7695a99175f59529069";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/php-code-coverage/zipball/6ce313bb110384148d1dc7695a99175f59529069";
          sha256 = "17viq976bf6hh60vmrmdh2ii39zgklp37hawv8n2a9x1crpc0zxf";
        };
      };
    };
    "phpunit/php-file-iterator" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phpunit-php-file-iterator-3ccaa29123548190af12fee7af078dcd7f3ddfab";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/php-file-iterator/zipball/3ccaa29123548190af12fee7af078dcd7f3ddfab";
          sha256 = "1s782pcxmyvi64shgpmdq9v3c0sfiq4zc7k8995r5l54p15brliw";
        };
      };
    };
    "phpunit/php-invoker" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phpunit-php-invoker-42e5c5cae0c65df12d1b1a3ab52bf3f50f244d88";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/php-invoker/zipball/42e5c5cae0c65df12d1b1a3ab52bf3f50f244d88";
          sha256 = "156599hrr0a0hlkyikbs5z3gssw1cyn1v8yppm2f7chrn2gl1jai";
        };
      };
    };
    "phpunit/php-text-template" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phpunit-php-text-template-a47af19f93f76aa3368303d752aa5272ca3299f4";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/php-text-template/zipball/a47af19f93f76aa3368303d752aa5272ca3299f4";
          sha256 = "1kacjd1zkz6i98vj52lvavgj97b71fv8kz6hd65cwxx896kfs3cw";
        };
      };
    };
    "phpunit/php-timer" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phpunit-php-timer-a0e12065831f6ab0d83120dc61513eb8d9a966f6";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/php-timer/zipball/a0e12065831f6ab0d83120dc61513eb8d9a966f6";
          sha256 = "1drj1mzamljq8h84mgvxg2ab81j6ijmxljsrjk2pyswnxbz94q58";
        };
      };
    };
    "phpunit/phpunit" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phpunit-phpunit-fc024931d6ad047404e9d86536735923fe63a06b";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/phpunit/zipball/fc024931d6ad047404e9d86536735923fe63a06b";
          sha256 = "01bv99pi7p2kv85brrlf86a466gafxi2g45zkh8xi9irga75bri9";
        };
      };
    };
    "sebastian/cli-parser" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-cli-parser-eeb759ad3146b7096fb59c3195d39e071cd409e3";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/cli-parser/zipball/eeb759ad3146b7096fb59c3195d39e071cd409e3";
          sha256 = "0znwsz89g43f2pi3qs3fcbgbazcm0rbqcww0p3xrnzg5aig2xji8";
        };
      };
    };
    "sebastian/comparator" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-comparator-3b070e608146cba00fd6fd1f0ffba89e5a8897fb";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/comparator/zipball/3b070e608146cba00fd6fd1f0ffba89e5a8897fb";
          sha256 = "1xvvd5ccysh4w4lka05kiahrga4k1d0gpc0jz9ih41yyvmm1v8xb";
        };
      };
    };
    "sebastian/complexity" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-complexity-c5651c795c98093480df79350cb050813fc7a2f3";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/complexity/zipball/c5651c795c98093480df79350cb050813fc7a2f3";
          sha256 = "0affzjx3m2z4dhmpnvflj1l61ykq51f0k5kh2m8sygp143rdhvhn";
        };
      };
    };
    "sebastian/diff" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-diff-a3fb6a298a265ff487a91bbea46e03cd01dbb226";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/diff/zipball/a3fb6a298a265ff487a91bbea46e03cd01dbb226";
          sha256 = "1p0iiaqbjlcn8sc3wi2ls9jbdc86d4qrwln7ahqhh3r6fpgr7m10";
        };
      };
    };
    "sebastian/environment" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-environment-6c9e487c9eb706a8d258102a1c0b0a3e53e86c2e";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/environment/zipball/6c9e487c9eb706a8d258102a1c0b0a3e53e86c2e";
          sha256 = "12hr5gxpqk5nwm2flyd12pfb0lm2qb0vyvqbgsxywf16m8961p3g";
        };
      };
    };
    "sebastian/exporter" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-exporter-24a3b69bba4a12ab615fca9d34680c5598d9ab7a";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/exporter/zipball/24a3b69bba4a12ab615fca9d34680c5598d9ab7a";
          sha256 = "0vhkkd38y8r6dcmhnwjrrm88cjbak3xlmmsw0g8gsph4plsp61yp";
        };
      };
    };
    "sebastian/file-filter" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-file-filter-33a26f394330f6faa7684bb9cc73afb7727aae93";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/file-filter/zipball/33a26f394330f6faa7684bb9cc73afb7727aae93";
          sha256 = "0vvw64580v9mlfd181g6d654wghvkk9ydi1b8ib21mf8ywgyvzd3";
        };
      };
    };
    "sebastian/git-state" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-git-state-792a952e0eba55b6960a48aeceb9f371aad1f76b";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/git-state/zipball/792a952e0eba55b6960a48aeceb9f371aad1f76b";
          sha256 = "1dh7smjk2y11m0rlc565l4c2r1qy0mnw4smjwl4cfzjkqi9v4mr3";
        };
      };
    };
    "sebastian/global-state" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-global-state-ba68ba79da690cf7eddefd3ce5b78b20b9ba9945";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/global-state/zipball/ba68ba79da690cf7eddefd3ce5b78b20b9ba9945";
          sha256 = "1v7v3smnb565mri4lwdzcfkk1vi7hkxrj3yf8sfmc71npwjzphs0";
        };
      };
    };
    "sebastian/lines-of-code" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-lines-of-code-d1b6f8fce682505dbd048977f1abedf1b8ad3ff8";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/lines-of-code/zipball/d1b6f8fce682505dbd048977f1abedf1b8ad3ff8";
          sha256 = "0jc2v3dai794q9a3snrrk65hrm86qnfvdn2cyxhin0ks90dr0ig8";
        };
      };
    };
    "sebastian/object-enumerator" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-object-enumerator-511064ecde82bd747e2ba2fab3dda8d977b59576";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/object-enumerator/zipball/511064ecde82bd747e2ba2fab3dda8d977b59576";
          sha256 = "0fpvm8m1dwfzzgc9dl3fzrg50m7ix2am94v74snlrjjpfxplckc9";
        };
      };
    };
    "sebastian/object-reflector" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-object-reflector-f71bbcdc4f95456b4622810bec64eb06372e25b2";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/object-reflector/zipball/f71bbcdc4f95456b4622810bec64eb06372e25b2";
          sha256 = "06lcxymp5lxlkalxzqvfxgab36zm5ig30s4wm9cxlyp3p16x7ld4";
        };
      };
    };
    "sebastian/recursion-context" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-recursion-context-32dba72f2b4642d6a93db22d6c0a9280ff2e3ca0";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/recursion-context/zipball/32dba72f2b4642d6a93db22d6c0a9280ff2e3ca0";
          sha256 = "0g9w49w0fajn0ccld99sq3nhxc6mssmiiymrznlbxpf6mx3a2k73";
        };
      };
    };
    "sebastian/type" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-type-bd1df467864cb95140414059a535b2d906173fcf";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/type/zipball/bd1df467864cb95140414059a535b2d906173fcf";
          sha256 = "0vzi84ja0l8jh155bv1jm6wa0fd3lx7j3pvyxgqjdp3lx7330pv3";
        };
      };
    };
    "sebastian/version" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-version-ad37a5552c8e2b88572249fdc19b6da7792e021b";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/version/zipball/ad37a5552c8e2b88572249fdc19b6da7792e021b";
          sha256 = "0dcqca5znng956763iwdwzplphy2ngr86di521g1dfsagl0nygfa";
        };
      };
    };
    "staabm/side-effects-detector" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "staabm-side-effects-detector-d8334211a140ce329c13726d4a715adbddd0a163";
        src = fetchurl {
          url = "https://api.github.com/repos/staabm/side-effects-detector/zipball/d8334211a140ce329c13726d4a715adbddd0a163";
          sha256 = "04kvzfgwpgncn3wm316l24a02lzds05z3nf83wrm9kk2vg52rn4h";
        };
      };
    };
    "theseer/tokenizer" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "theseer-tokenizer-7989e43bf381af0eac72e4f0ca5bcbfa81658be4";
        src = fetchurl {
          url = "https://api.github.com/repos/theseer/tokenizer/zipball/7989e43bf381af0eac72e4f0ca5bcbfa81658be4";
          sha256 = "1d0rsx96jylbjvnhi0ylwrq5pxcmlmqir8n63cajy2zrvhzngkcp";
        };
      };
    };
  };
in
composerEnv.buildPackage {
  inherit packages devPackages noDev;
  name = "vpsadmin-webui";
  src = composerEnv.filterSrc ./.;
  executable = false;
  symlinkDependencies = false;
  meta = { };
}
