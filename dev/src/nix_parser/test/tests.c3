// tests.c3
// Main test suite for dev-shell - using C3 test conventions

module tests @test;

import std::io;
import std::io::file;
import std::core::test;
import nix_parser;
import ts;
import test_utils;

fn void test_nix_tree_serialization_1() @test {
  @pool() {
    String source = `{ foo = 1 + 2; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_tree_str = nix_parser::serialize_tree(expr);
    test::eq(nix_tree_str, `attrset(multiline=false):
 binding(foo):
  binop(+):
   int(1)
   int(2)
`);
  };
}

fn void test_nix_code_serialization_1() @test {
  @pool() {
    String source = `{ foo = 1 + 2; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{ foo = (1 + 2); }`);
  };
}

fn void test_nix_tree_serialization_2() @test {
  @pool() {
    String source = `
{
  description = "Some test flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tts.url = "path:./tts";
  };

  outputs = { self, nixpkgs, flake-utils, tts }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        kyoki_tts = tts.packages.${system}.default;
        deps = with pkgs; [
          gcc
          go
          gopls
          kyoki_tts
        ];
      in
      {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_tree_str = nix_parser::serialize_tree(expr);
    test::eq(nix_tree_str, `attrset(multiline=true):
 binding(description):
  string(Some test flake)
 binding(inputs):
  attrset(multiline=true):
   binding(nixpkgs.url):
    string(github:NixOS/nixpkgs/nixos-unstable)
   binding(flake-utils.url):
    string(github:numtide/flake-utils)
   binding(tts.url):
    string(path:./tts)
 binding(outputs):
  function:
   formals:
    formal(self)
    formal(nixpkgs)
    formal(flake-utils)
    formal(tts)
   apply:
    select(lib.eachDefaultSystem):
     var(flake-utils)
    paren:
     function:
      formals:
       formal(system)
      let(multiline=true):
       binding(pkgs):
        select(legacyPackages.${system}):
         var(nixpkgs)
       binding(kyoki_tts):
        select(packages.${system}.default):
         var(tts)
       binding(deps):
        with:
         var(pkgs)
         body:
          list(multiline=true):
           var(gcc)
           var(go)
           var(gopls)
           var(kyoki_tts)
       in:
        attrset(multiline=true):
         binding(packages.dev-shell):
          apply:
           select(mkShell):
            var(dev-shell)
           attrset(multiline=false):
            binding(inherit):
             inherit(pkgs)
            binding(inherit):
             inherit(deps)
         binding(devShells.default):
          apply:
           select(mkShell):
            var(dev-shell)
           attrset(multiline=false):
            binding(inherit):
             inherit(pkgs)
            binding(inherit):
             inherit(deps)
`);
  };
}

fn void test_nix_code_serialization_2() @test {
  @pool() {
    String source = `
{
  description = "Some test flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tts.url = "path:./tts";
  };

  outputs = { self, nixpkgs, flake-utils, tts }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        kyoki_tts = tts.packages.${system}.default;
        deps = with pkgs; [
          gcc
          go
          gopls
          kyoki_tts
        ];
      in
      {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{
  description = "Some test flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tts.url = "path:./tts";
  };
  outputs = {self, nixpkgs, flake-utils, tts}: flake-utils.lib.eachDefaultSystem ({system}: let
    pkgs = nixpkgs.legacyPackages.${system};
    kyoki_tts = tts.packages.${system}.default;
    deps = with pkgs; [
      gcc
      go
      gopls
      kyoki_tts
    ];
  in {
    packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
    devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };
  });
}`);
  };
}


fn void test_nix_code_output_removal_1() @test {
  @pool() {
    String source = `
{
  description = "Some test flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tts.url = "path:./tts";
  };

  outputs = { self, nixpkgs, flake-utils, tts }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        kyoki_tts = tts.packages.${system}.default;
        deps = with pkgs; [
          gcc
          go
          gopls
          kyoki_tts
        ];
      in
      {
        packages.tts = kyoki_tts;
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    nix_parser::remove_outputs_except_devshell(expr);
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{
  description = "Some test flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tts.url = "path:./tts";
  };
  outputs = {self, nixpkgs, flake-utils, tts}: flake-utils.lib.eachDefaultSystem ({system}: let
    pkgs = nixpkgs.legacyPackages.${system};
    kyoki_tts = tts.packages.${system}.default;
    deps = with pkgs; [
      gcc
      go
      gopls
      kyoki_tts
    ];
  in {
    packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
  });
}`);
  };
}

fn void test_nix_remove_unused_let_definitions() @test {
  @pool() {
    String source = `let
      pkgs = nixpkgs.legacyPackages.${system};
      kyoki_tts = tts.packages.${system}.default;
      deps = with pkgs; [
        gcc
        go
        gopls
        kyoki_tts
      ];
    in {
      packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
    };`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* let_expr = nix_parser::tr_source(root, &source)!!;
    nix_parser::remove_unused_let_definitions(let_expr);
    String nix_code_str = nix_parser::serialize_code(let_expr);
    test::eq(nix_code_str, `let
  pkgs = nixpkgs.legacyPackages.${system};
  deps = with pkgs; [
    gcc
    go
    gopls
    kyoki_tts
  ];
in {
  packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
}`);
  };
}

fn void test_nix_remove_unused_flake_inputs() @test {
  @pool() {
    String source = `
{
  description = "Some test flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    tts.url = "path:./tts";
  };

  outputs = { self, nixpkgs, flake-utils, tts }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        deps = with pkgs; [
          gcc
          go
          gopls
        ];
      in
      {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    nix_parser::remove_unused_flake_inputs(expr);
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{
  description = "Some test flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = {self, nixpkgs, flake-utils}: flake-utils.lib.eachDefaultSystem ({system}: let
    pkgs = nixpkgs.legacyPackages.${system};
    deps = with pkgs; [
      gcc
      go
      gopls
    ];
  in {
    packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
  });
}`);
  };
}
