{
  description = "dev-shell dev env";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        deps = with pkgs; [
          clang
          pkg-config
          cmake
          c3c
        ];

        dev-shell-bin = pkgs.stdenv.mkDerivation {
          pname = "dev-shell-bin";
          version = "0.2.0";
          src = self;
          nativeBuildInputs = [ pkgs.c3c ];
          buildPhase = ''
            c3c build
          '';
          installPhase = ''
            mkdir -p $out/bin
            cp build/dev-shell $out/bin/dev-shell
            chmod +x $out/bin/dev-shell
          '';
        };
      in
      {
        packages.default = dev-shell-bin;
        devShells.default = pkgs.mkShell {
          buildInputs = deps;
          shellHook = '''';
        };
      }
    );
}
