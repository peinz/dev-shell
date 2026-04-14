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
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = deps;
          shellHook = '''';
        };
      }
    );
}
