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
        name = "endroid-qr-code-5630e192948b466d418608ecce697465d20260af";
        src = fetchurl {
          url = "https://api.github.com/repos/endroid/qr-code/zipball/5630e192948b466d418608ecce697465d20260af";
          sha256 = "011jm565rd4rw45aqkiyfs2ai4ikmic7vp3v2045f5p2jznzydk3";
        };
      };
    };
    "haveapi/client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "haveapi-client-112301476e4123998914c1fcb7cbbbf0e5c5e0ce";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/haveapi-client-php/zipball/112301476e4123998914c1fcb7cbbbf0e5c5e0ce";
          sha256 = "14cm899iwkm6z29fwzvj7fyxfg1mh9g02wy4axnyj80wdcc4m7is";
        };
      };
    };
    "nategood/httpful" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "nategood-httpful-0cded3ea97ba905600de9ceb9ef13f3ab681587c";
        src = fetchurl {
          url = "https://api.github.com/repos/nategood/httpful/zipball/0cded3ea97ba905600de9ceb9ef13f3ab681587c";
          sha256 = "13kcpb4j2n1n4fln7v0s9il729s3mmmm3s4akq3azs671pyr2i6h";
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
