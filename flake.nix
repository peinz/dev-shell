{
  description = "dev-shell that wraps current shell";

  outputs = { self }: {
    mkShell = { pkgs, deps }: let
      pkgConfigPath = pkgs.lib.concatStringsSep ":" (
        pkgs.lib.concatMap (p: [
          "${p}/lib/pkgconfig"
          "${p}/share/pkgconfig"
        ]) deps);

      text = /* bash */ ''
        #!/usr/bin/env bash

        # base shell path
        shell=""
        if [ -n "''${NIX_DEVSHELL_USER_SHELL:-}" ];
          then shell=''$NIX_DEVSHELL_USER_SHELL
          else shell=${pkgs.bash}/bin/bash 
        fi

        # env name
        if [ -n "''${1:-}" ];
          then export NIX_DEVSHELL_ENV=''$1
          else export NIX_DEVSHELL_ENV=dev-shell
        fi

        # setup env
        export PATH="${pkgs.lib.makeBinPath deps}:''$PATH"
        export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath deps}:''${LD_LIBRARY_PATH:-}"
        export PKG_CONFIG_PATH="${pkgConfigPath}:''${PKG_CONFIG_PATH:-}"
      
        # start shell
        exec ''$shell
      '';
    in pkgs.writeShellApplication {
      name = "dev-shell";
      runtimeInputs = [ pkgs.bash ];
      inherit text;
    };
  };
}





