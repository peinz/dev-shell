{
  description = "dev-shell dev env";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tree-sitter.url = "github:tree-sitter/tree-sitter/aff9b9d92e628bdb159189b7066baa00e8f7535e";
    tree-sitter-nix.url = "github:nix-community/tree-sitter-nix/eabf96807ea4ab6d6c7f09b671a88cd483542840";
  };

  outputs = { self, nixpkgs, flake-utils, tree-sitter, tree-sitter-nix }:
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
          version = "0.3.3";
          src = self;
          nativeBuildInputs = [ pkgs.c3c pkgs.gcc ];

          buildPhase = ''
            # Populate submodule directories from flake inputs
            # (submodule dirs are empty gitlinks in the flake tarball)
            mkdir -p src/nix_parser/lib/tree-sitter
            # tree-sitter repo has lib/src/ and lib/include/ — the Makefile
            # expects tree-sitter/lib/src/lib.c and tree-sitter/lib/include/
            cp -r ${tree-sitter}/lib src/nix_parser/lib/tree-sitter/lib

            mkdir -p src/nix_parser/lib/tree-sitter-nix
            cp -r ${tree-sitter-nix}/src src/nix_parser/lib/tree-sitter-nix/src
            chmod -R u+w src/nix_parser/lib/tree-sitter src/nix_parser/lib/tree-sitter-nix

            # Build tree-sitter static lib and nix parser objects
            make -C src/nix_parser/lib all nix-parser

            # Build the C3 project
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
