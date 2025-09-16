{ ruby, runCommand }:
runCommand "vmexec"
  {
    buildInputs = [ ruby ];
  }
  ''
    mkdir $out
    cp -r ${../../vmexec}/. $out/
    chmod +w $out/bin
    patchShebangs $out/bin
  ''
