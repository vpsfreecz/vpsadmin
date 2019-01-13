{ lib, erlang, buildMix, glibcLocales, releaseConfig ? null, releaseEnv,
  releaseName, mixEnv ? "prod" }:
buildMix rec {
  name = "core-${version}-${releaseName}";
  version = "0.1.0";
  src = ../../core;
  beamDeps = [];
  buildPhase = ''
    runHook preBuild

    export HEX_HOME=`pwd`
    export MIX_ENV=${mixEnv}
    export LOCALE_ARCHIVE="${glibcLocales}/lib/locale/locale-archive"
    export LANG="en_US.UTF-8"

    cat rel/config.base.exs > rel/config.exs
    ${lib.optionalString (releaseConfig != null) ''
      cat ${releaseConfig} >> rel/config.exs
    ''}

    mix release --env ${releaseEnv} --name=${releaseName} --no-tar

    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -rp _build/${mixEnv}/rel/${releaseName}/* $out/

    runHook postInstall

    echo yo
    echo
    echo
    echo $out
    echo
    echo
  '';
}
