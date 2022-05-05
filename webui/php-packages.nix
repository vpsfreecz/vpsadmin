{composerEnv, fetchurl, fetchgit ? null, fetchhg ? null, fetchsvn ? null, noDev ? false}:

let
  packages = {
    "bacon/bacon-qr-code" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "bacon-bacon-qr-code-d70c840f68657ce49094b8d91f9ee0cc07fbf66c";
        src = fetchurl {
          url = "https://api.github.com/repos/Bacon/BaconQrCode/zipball/d70c840f68657ce49094b8d91f9ee0cc07fbf66c";
          sha256 = "0k2z8a6qz5xg1p85vwcp58yqbiw8bmnp3hg2pjcaqlimnf65v058";
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
        name = "endroid-qr-code-9109eb7790ece1d46b1ab40eb7f375bbd6e7cb5d";
        src = fetchurl {
          url = "https://api.github.com/repos/endroid/qr-code/zipball/9109eb7790ece1d46b1ab40eb7f375bbd6e7cb5d";
          sha256 = "1bnfrcwp9f2qj0fhn0ks09040y5hggij7syny5yjb0i03w8164pb";
        };
      };
    };
    "haveapi/client" = {
      targetDir = "";
      src = composerEnv.buildZipPackage {
        name = "haveapi-client-0b6f052c1ba8512c5b1ea5277961ff75a5e5091e";
        src = fetchurl {
          url = "https://api.github.com/repos/vpsfreecz/haveapi-client-php/zipball/0b6f052c1ba8512c5b1ea5277961ff75a5e5091e";
          sha256 = "0dbrvl2n1f7c6al0khry01rkk9gryig5g1dicgxj4gxc6l7n5zkg";
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
