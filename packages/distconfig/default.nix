{ ruby, runCommandNoCC }:
runCommandNoCC "distconfig"
  {
    buildInputs = [ ruby ];
  }
  ''
    mkdir $out
    cp -r ${../../distconfig}/. $out/
    chmod +w $out/bin
    patchShebangs $out/bin
  ''
