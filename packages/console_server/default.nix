{ ruby, runCommandNoCC }:
runCommandNoCC "console-server"
  {
    buildInputs = [ ruby ];
  }
  ''
    mkdir $out
    cp -r ${../../console_server}/. $out/
    chmod +w $out/bin
    patchShebangs $out/bin
  ''
