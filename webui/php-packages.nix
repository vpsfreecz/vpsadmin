{composerEnv, fetchurl, fetchgit ? null, fetchhg ? null, fetchsvn ? null, noDev ? false}:

let
  packages = {
    "bacon/bacon-qr-code" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "bacon-bacon-qr-code-f73543ac4e1def05f1a70bcd1525c8a157a1ad09";
        src = fetchurl {
          url = "https://api.github.com/repos/Bacon/BaconQrCode/zipball/f73543ac4e1def05f1a70bcd1525c8a157a1ad09";
          sha256 = "1df22bfrc8q62qz8brrs8p2rmmv5gsaxdyjrd2ln6d6j7i4jkjpk";
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
        name = "endroid-qr-code-98f6d4024289ad3a8d7f3e63cab947ef6929dcdb";
        src = fetchurl {
          url = "https://api.github.com/repos/endroid/qr-code/zipball/98f6d4024289ad3a8d7f3e63cab947ef6929dcdb";
          sha256 = "10ydi0qggrafzmmq01a7ghj61ybjzgy8pra5ff9l5p96jg5ppgn4";
        };
      };
    };
    "haveapi/client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "haveapi-client-6908fad404c29484a7a09255755d481235916618";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/haveapi-client-php/zipball/6908fad404c29484a7a09255755d481235916618";
          sha256 = "02k28g04gj67vcxhnqxl2sx4afdcf4ggka6gv8v3bppzn8hbvkbm";
        };
      };
    };
    "nategood/httpful" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "nategood-httpful-c1cd4d46a4b281229032cf39d4dd852f9887c0f6";
        src = fetchurl {
          url = "https://api.github.com/repos/nategood/httpful/zipball/c1cd4d46a4b281229032cf39d4dd852f9887c0f6";
          sha256 = "09px7pcw5l87b5672qrg88ymx4351h3p3i2zm1rjk32xh6ng5yxk";
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
