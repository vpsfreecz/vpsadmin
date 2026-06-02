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
        name = "guzzlehttp-guzzle-e7412b3180912c01650cc66647f18c1d1cbe9b94";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/guzzle/zipball/e7412b3180912c01650cc66647f18c1d1cbe9b94";
          sha256 = "05w51b7zd66n7a7vlkgx8yvgsk6algknsmnnqqkh9wpqzymmclqq";
        };
      };
    };
    "guzzlehttp/promises" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "guzzlehttp-promises-09e8a212562fb1fb6a512c4156ed71525969d6c2";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/promises/zipball/09e8a212562fb1fb6a512c4156ed71525969d6c2";
          sha256 = "1irpw72x16g28bgr1n3396l4yl6ngrfj9vwq304y2rgp9xxi5ydm";
        };
      };
    };
    "guzzlehttp/psr7" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "guzzlehttp-psr7-d2a1a094e396da8957e797489fddaf860c340cfc";
        src = fetchurl {
          url = "https://api.github.com/repos/guzzle/psr7/zipball/d2a1a094e396da8957e797489fddaf860c340cfc";
          sha256 = "016hv606ys6pxnmyslggqfyhd3n1cbbdqill57dqbq3d6b94vji5";
        };
      };
    };
    "haveapi/client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "haveapi-client-ffd2d3e4a7617b0a5a0266bc0ef5caed2d20929a";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/haveapi-client-php/zipball/ffd2d3e4a7617b0a5a0266bc0ef5caed2d20929a";
          sha256 = "0d96cc98skdkhsmg38yhq18aibdpccsj077j7aawhyjr0xhv408h";
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
        name = "symfony-deprecation-contracts-50f59d1f3ca46d41ac911f97a78626b6756af35b";
        src = fetchurl {
          url = "https://api.github.com/repos/symfony/deprecation-contracts/zipball/50f59d1f3ca46d41ac911f97a78626b6756af35b";
          sha256 = "0ssbi6dgnd101f303ivzdy2hjpjlhhzczg0ffbjhnlx1wjy3gmh0";
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
        name = "myclabs-deep-copy-07d290f0c47959fd5eed98c95ee5602db07e0b6a";
        src = fetchurl {
          url = "https://api.github.com/repos/myclabs/DeepCopy/zipball/07d290f0c47959fd5eed98c95ee5602db07e0b6a";
          sha256 = "0ch1sz2lki1qnb49r2zww7ryk6i4ckyr04p1p9hmiszfi9fr631y";
        };
      };
    };
    "nikic/php-parser" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "nikic-php-parser-dca41cd15c2ac9d055ad70dbfd011130757d1f82";
        src = fetchurl {
          url = "https://api.github.com/repos/nikic/PHP-Parser/zipball/dca41cd15c2ac9d055ad70dbfd011130757d1f82";
          sha256 = "1qiv7qp87p0p39yqdcffakvdb533gnx57iz966wv7hkhprqsn2lb";
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
        name = "phpunit-php-code-coverage-3719c5b6c045761798238ebacfee1fe06e4ce5be";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/php-code-coverage/zipball/3719c5b6c045761798238ebacfee1fe06e4ce5be";
          sha256 = "1pxgrcpvr6vpfp6dpfa2cbsnbrhgvmy6w9g26s6rnpm57y225jfg";
        };
      };
    };
    "phpunit/php-file-iterator" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "phpunit-php-file-iterator-6e5aa1fb0a95b1703d83e721299ee18bb4e2de50";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/php-file-iterator/zipball/6e5aa1fb0a95b1703d83e721299ee18bb4e2de50";
          sha256 = "12llfmn6lap1125nkay8fvb9gyvyx503ji8fw0dzdh1iimbpbpda";
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
        name = "phpunit-phpunit-ddf7f25d9ee9652b464475d7f3bacde2613e355e";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/phpunit/zipball/ddf7f25d9ee9652b464475d7f3bacde2613e355e";
          sha256 = "1236s9wjfay66pkfdqq5j5cyrg6kvy3xbd98d0xja07r1bwyhn4r";
        };
      };
    };
    "sebastian/cli-parser" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-cli-parser-48a4654fa5e48c1c81214e9930048a572d4b23ca";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/cli-parser/zipball/48a4654fa5e48c1c81214e9930048a572d4b23ca";
          sha256 = "0rb7l29drxlgl2060nw1ng5x8lwlm16ipxgyggrkv6sn44fpy8kb";
        };
      };
    };
    "sebastian/comparator" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-comparator-ce999bf08b2c387a5423fe56961c32eed3f88089";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/comparator/zipball/ce999bf08b2c387a5423fe56961c32eed3f88089";
          sha256 = "0d63881h0a7ix1s28d77ap677nwqwk2ivdqhw6pvp8rxg7zs02ml";
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
        name = "sebastian-diff-b36d33b6e796513de7cb7df053afb3f55eefcd47";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/diff/zipball/b36d33b6e796513de7cb7df053afb3f55eefcd47";
          sha256 = "15dy6930min4h2p1iv3q0xx1gvzqa8kn9cdydg60g8z8b8if15lf";
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
        name = "sebastian-exporter-c0d29a945f8cf82f300a05e69874508e307ca4c6";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/exporter/zipball/c0d29a945f8cf82f300a05e69874508e307ca4c6";
          sha256 = "0mvs2s4cf28hswkmbbhfyf49rf5hz2a6ssl9wlarsp5d0q4ba0zj";
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
        name = "sebastian-lines-of-code-d2cff273a90c79b0eb590baa682d4b5c318bdbb7";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/lines-of-code/zipball/d2cff273a90c79b0eb590baa682d4b5c318bdbb7";
          sha256 = "1a88q508z6x9bvyw5fjbmj7cjqfa7ccb90x91h910944sff6qk76";
        };
      };
    };
    "sebastian/object-enumerator" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-object-enumerator-b39ab125fd9a7434b0ecbc4202eebce11a98cfc5";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/object-enumerator/zipball/b39ab125fd9a7434b0ecbc4202eebce11a98cfc5";
          sha256 = "0cfdsxg6qh2qafwfgm6pnihh6viybgi3jx7c8kjlpk57xqyi48sb";
        };
      };
    };
    "sebastian/object-reflector" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-object-reflector-3ca042c2c60b0eab094f8a1b6a7093f4d4c72200";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/object-reflector/zipball/3ca042c2c60b0eab094f8a1b6a7093f4d4c72200";
          sha256 = "0yf6iss844qdiqz679xv4dkq210y7a4a686fqkkq19gz9z8x3zr2";
        };
      };
    };
    "sebastian/recursion-context" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-recursion-context-74c5af21f6a5833e91767ca068c4d3dfec15317e";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/recursion-context/zipball/74c5af21f6a5833e91767ca068c4d3dfec15317e";
          sha256 = "1znzsh41xixsslgyvhg0sjwr1470d4blv01mdf350h1wzpmxclcv";
        };
      };
    };
    "sebastian/type" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "sebastian-type-fee0309275847fefd7636167085e379c1dbf6990";
        src = fetchurl {
          url = "https://api.github.com/repos/sebastianbergmann/type/zipball/fee0309275847fefd7636167085e379c1dbf6990";
          sha256 = "1cw32i6ivfgjksm5qr16spzm0z8m12f4ajq8bjx0z3846ykmk8v6";
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
