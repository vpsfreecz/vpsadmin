{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  packages = with pkgs; [
    go
    gopls
    gotools
    go-tools
    git
    novnc
  ];

  shellHook = ''
    NOVNC_DIR="${pkgs.novnc}/share/webapps/novnc"

    cat > ./config.nix.json <<EOF
    {
      "novnc_dir": "$NOVNC_DIR"
    }
    EOF

    echo "Wrote ./config.nix.json with novnc_dir=$NOVNC_DIR"
    echo "Example run:"
    echo "  go run ./cmd/vnc_router -config ./config.base.json -config ./config.nix.json -config ./config.secrets.json"
  '';
}
