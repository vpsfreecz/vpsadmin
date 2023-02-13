{composerEnv, fetchurl, fetchgit ? null, fetchhg ? null, fetchsvn ? null, noDev ? false}:

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
        name = "dasprid-enum-5abf82f213618696dda8e3bf6f64dd042d8542b2";
        src = fetchurl {
          url = "https://api.github.com/repos/DASPRiD/Enum/zipball/5abf82f213618696dda8e3bf6f64dd042d8542b2";
          sha256 = "0rs7i1xiwhssy88s7bwnp5ri5fi2xy3fl7pw6l5k27xf2f1hv7q6";
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
    "haveapi/client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "haveapi-client-70ca99bab02f54c08a1d4dedf822f0d8fe6d1bf8";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/haveapi-client-php/zipball/70ca99bab02f54c08a1d4dedf822f0d8fe6d1bf8";
          sha256 = "0wz3f9dyzn7brnsbspjyxc2jmcmv1mzj81ilnvjky1sw0a2l4nhr";
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
  };
  devPackages = {};
in
composerEnv.buildPackage {
  inherit packages devPackages noDev;
  name = "vpsadmin-webui";
  src = ./.;
  executable = false;
  symlinkDependencies = false;
  meta = {};
}
