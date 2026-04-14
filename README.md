# dev-shell

A Nix-based development shell that wraps your current shell with development dependencies.

## Purpose

When using `nix develop`, the entire project directory gets copied to the nix store. For large projects, this can be slow because even files not needed for the development environment (like source code, assets, documentation) get copied.

**dev-shell** solves this by:
1. Extracting the essential `pkgs` and `deps` from your project's root `flake.nix`
2. Generating a minimal `.dev-shell/` subdirectory containing only the flake configuration needed to build the dev shell
3. Building and entering the shell from that isolated subdirectory

This way, only the `.dev-shell/` directory is copied to the nix store - not your entire project.

## Features

- **Automatic extraction**: Parses root `flake.nix` to extract `pkgs` and `deps` definitions using regex
- **Subdirectory isolation**: Generates minimal flake in `.dev-shell/` for efficient nix store copying
- **Auto-building**: Checks if `result/bin/dev-shell` exists, builds with `nix build .#dev-shell` if needed
- **Custom env vars**: Supports passing custom environment variables via the `env` parameter
- **Git integration**: Automatically adds generated files to git for nix compatibility

## Usage

### For Projects Using dev-shell

Add dev-shell to your project's `flake.nix`:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dev-shell.url = "github:peinz/dev-shell";
  };

  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        deps = with pkgs; [
          gcc
          go
          gopls
          deno
          imagemagick
        ];
      in
      {
        devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };
      }
    );
}
```

Then run the dev-shell binary from any subdirectory of your project:

```bash
# Build and enter the shell
dev-shell

# Or if you have the binary already built
./result/bin/dev-shell
```

The dev-shell binary will:
1. Search upward from current directory to find the root `flake.nix`
2. Extract `pkgs` and `deps` from it
3. Generate `.dev-shell/flake.nix` with the extracted configuration
4. Build the shell if not already built
5. Execute the built shell

### Custom Environment Variables

You can pass custom environment variables to the shell:

```nix
dev-shell.mkShell { inherit pkgs; inherit deps; env = { MY_VAR = "value"; }; }
```

These will be exported when the shell starts.

## How It Works

### 1. Finding the Root flake.nix

The binary starts from the current working directory and searches upward until it finds a `flake.nix`. That directory becomes the project root.

### 2. Extracting Configuration

It uses regex to extract:
- `pkgs` - the package set definition (e.g., `import nixpkgs { inherit system; }`)
- `deps` - the list of dependencies (e.g., `[ gcc go deno ]`)

### 3. Generating .dev-shell/flake.nix

A new minimal flake is generated in `.dev-shell/`:
```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dev-shell.url = "github:peinz/dev-shell";
  };

  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = <extracted-pkgs-definition>;
        deps = with pkgs; [
          <extracted-deps>
        ];
      in
      {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };
      }
    );
}
```

### 4. Building and Entering

- If `.dev-shell/result/bin/dev-shell` doesn't exist, it runs `nix build .#dev-shell`
- The built shell is then executed with the project directory name as argument
- The shell automatically creates `.dev-shell/.gitignore` containing `result`

## File Structure

```
dev-shell/
├── flake.nix              # Main dev-shell library providing mkShell
├── README.md             # This file
└── dev/
    ├── dev-shell.c3      # C3 implementation of the dev-shell binary
    ├── dev-shell         # Compiled dev-shell binary
    ├── flake.nix         # Development environment for working on dev-shell
    └── test/
        └── flake.nix     # Example usage of dev-shell
```

## Current Limitations

- Only extracts simple `pkgs` definitions like `import nixpkgs { inherit system; }` or `nixpkgs.legacyPackages.${system}`
- Only extracts simple `deps` lists directly from `pkgs`
- Complex let bindings with custom variables (e.g., `kyoki_tts = tts.packages.${system}.default`) are not fully supported yet
- Only supports bash as the wrapped shell

## Development

To work on dev-shell itself:

```bash
cd dev
nix develop
# or use the compiled binary
./dev-shell
```

## License

MIT