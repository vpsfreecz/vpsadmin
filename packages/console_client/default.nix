{ ruby, runCommandNoCC }:
runCommandNoCC "console-client"
  {
    buildInputs = [ ruby ];
  }
  ''
    mkdir $out
    cp -r ${../../console_client}/. $out/
    chmod +w $out/bin
    patchShebangs $out/bin
  ''
