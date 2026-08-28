// tests.c3
// Main test suite for dev-shell - using C3 test conventions

module tests @test;

import std::io;
import std::io::file;
import std::core::test;
import std::collections::list;
import nix_parser;
import ts;
import test_utils;


fn void test_nix_inherit_multiple_names_roundtrip() @test {
  @pool() {
    // `inherit pkgs deps;` (one inherit, two names) must round-trip with names
    // separated by a space, not concatenated into `inherit pkgsdeps;`.
    String source = `{ inherit pkgs deps; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{ inherit pkgs deps; }`);
  };
}

fn void test_nix_inherit_single_name_roundtrip() @test {
  @pool() {
    String source = `{ inherit pkgs; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{ inherit pkgs; }`);
  };
}

fn void test_nix_inherit_three_names_roundtrip() @test {
  @pool() {
    String source = `{ inherit pkgs deps foo; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{ inherit pkgs deps foo; }`);
  };
}

fn void test_nix_inherit_multiple_in_mkshell() @test {
  @pool() {
    // Full flake using `inherit pkgs deps;` (combined) inside mkShell must
    // serialize back to `inherit pkgs deps;`, not `inherit pkgsdeps;`.
    String source = `
{
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        deps = with pkgs; [ gcc ];
      in {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::@check(test_utils::string_contains(nix_code_str, "inherit pkgs deps;"));
    test::@check(!test_utils::string_contains(nix_code_str, "inherit pkgsdeps;"));
  };
}

// Regression: find_let_in_outputs must handle parenthesized function arguments.
// `eachDefaultSystem (system: let ... in ...)` wraps the function in PAREN.
// Without unwrapping PAREN, find_let_in_outputs returned null and the let
// bindings were never pruned.
fn void test_find_let_in_outputs_with_paren() @test {
  @pool() {
    String source = `
{
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        unused = "drop me";
        deps = with pkgs; [ gcc ];
      in {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;

    // find_let_in_outputs must return non-null despite PAREN wrapper
    Expression* let_expr = nix_parser::find_let_in_outputs(expr);
    test::@check(let_expr != null);

    // The let body must have bindings (packages.dev-shell)
    if (let_expr != null) {
      Expression* let_body = let_expr.as_let_expression.body;
      int body_bindings = (int)let_body.as_attrset_expression.bindings.size;
      test::@check(body_bindings == 1);
    }

    // After removing unused let definitions, `unused` must be gone
    if (let_expr != null) {
      nix_parser::remove_unused_let_definitions(let_expr);
    }
    String result = nix_parser::serialize_code(expr);
    test::@check(!test_utils::string_contains(result, "unused"));
    test::@check(test_utils::string_contains(result, "packages.dev-shell"));
    test::@check(test_utils::string_contains(result, "deps"));
  };
}

// Regression: inherit with multiple names must serialize with space separators.
// Previously `inherit pkgs deps;` serialized as `inherit pkgsdeps;`.
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
  outputs = {self, nixpkgs, flake-utils, tts}: flake-utils.lib.eachDefaultSystem (system: let
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
  outputs = {self, nixpkgs, flake-utils, tts}: flake-utils.lib.eachDefaultSystem (system: let
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
  outputs = {self, nixpkgs, flake-utils}: flake-utils.lib.eachDefaultSystem (system: let
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

fn void test_nix_preserves_pinned_nixpkgs() @test {
  @pool() {
    String source = `
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    dev-shell.url = "github:peinz/dev-shell";
  };

  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        deps = with pkgs; [
          nodejs_20
          pnpm
        ];
      in
      {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        devShells.default = pkgs.mkShell { buildInputs = deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    nix_parser::remove_unused_flake_inputs(expr);
    Expression* let_expr = nix_parser::find_let_in_outputs(expr);
    if (let_expr != null) {
      nix_parser::remove_unused_let_definitions(let_expr);
    }
    String result = nix_parser::serialize_code(expr);

    // The pinned nixpkgs URL must be preserved, not replaced with nixos-unstable
    test::@check(test_utils::string_contains(result, "nixos-24.05"));
    test::@check(!test_utils::string_contains(result, "nixos-unstable"));
    // devShells.default should be stripped, packages.dev-shell kept
    test::@check(test_utils::string_contains(result, "packages.dev-shell"));
    test::@check(!test_utils::string_contains(result, "devShells.default"));
  };
}

fn void test_nix_indented_string() @test {
  @pool() {
    String source = `{ hook = ''
      echo hello
      mkdir -p $out
    ''; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    // The serialized code should start with { and end with }, contain the '' markers
    test::@check(nix_code_str[0] == '{');
    usz len = nix_code_str.len;
    test::@check(nix_code_str[len - 1] == '}');
    usz idx;
    if (try i = nix_code_str.index_of("''")) {
      idx = i;
    } else {
      test::@check(false);  // should contain '' markers
    }
  };
}

fn void test_nix_float_and_if() @test {
  @pool() {
    // Float test
    String float_source = `{ pi = 3.14; }`;
    TsTree* float_tree = nix_parser::parse_ts_nix_tree(float_source);
    defer ts::tree_delete(float_tree);
    TsNode float_root = ts::tree_root_node(float_tree);
    Expression* float_expr = nix_parser::tr_source(float_root, &float_source)!!;
    String float_code = nix_parser::serialize_code(float_expr);
    test::eq(float_code, `{ pi = 3.14; }`);

    // If-expression (raw fallback) test
    String if_source = `{ x = if true then 1 else 2; }`;
    TsTree* if_tree = nix_parser::parse_ts_nix_tree(if_source);
    defer ts::tree_delete(if_tree);
    TsNode if_root = ts::tree_root_node(if_tree);
    Expression* if_expr = nix_parser::tr_source(if_root, &if_source)!!;
    String if_code = nix_parser::serialize_code(if_expr);
    // Raw fallback preserves text; check it doesn't crash and contains the if expression
    test::@check(if_code.len > 0);
    usz if_idx;
    if (try i = if_code.index_of("if true then 1 else 2")) {
      if_idx = i;
    } else {
      test::@check(false);
    }
  };
}

fn void test_nix_flake_with_derivation() @test {
  @pool() {
    String source = `
{
  description = "Some test";
  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages.default = pkgs.stdenv.mkDerivation {
        name = "test";
        version = "0.1";
        src = self;
        buildPhase = ''
          echo "Building..."
          mkdir -p $out/bin
        '';
        installPhase = ''
          cp result $out/bin/
        '';
      };
    };
}`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    // Verify it doesn't crash and preserves structure
    test::@check(nix_code_str[0] == '{');
    usz len = nix_code_str.len;
    test::@check(nix_code_str[len - 1] == '}');

    // Apply remove_outputs_except_devshell and verify it still works (no dev-shell output here)
    nix_parser::remove_outputs_except_devshell(expr);
    String after_code = nix_parser::serialize_code(expr);
    test::@check(after_code.len > 0);
  };
}

fn void test_find_binding_value() @test {
  @pool() {
    String source = `
{
  description = "Test flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };
  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { inherit system; };
      foo = "hello";
      deps = with pkgs; [ gcc foo ];
    in {
      packages.dev-shell = dev-shell.mkShell { inherit pkgs deps; };
    };
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* ast = nix_parser::tr_source(root, &source)!!;

    Expression* pkgs_expr = nix_parser::find_binding_value(ast, "pkgs");
    test::@check(pkgs_expr != null);

    Expression* deps_expr = nix_parser::find_binding_value(ast, "deps");
    test::@check(deps_expr != null);

    Expression* foo_expr = nix_parser::find_binding_value(ast, "foo");
    test::@check(foo_expr != null);

    Expression* missing = nix_parser::find_binding_value(ast, "nonexistent");
    test::@check(missing == null);
  };
}

fn void test_transitive_bindings_simple() @test {
  @pool() {
    String source = `
{
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        foo = pkgs.stdenv.mkDerivation { name = "foo"; };
        deps = with pkgs; [ gcc foo ];
      in {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* ast = nix_parser::tr_source(root, &source)!!;

    List{String} bindings;
    bindings.init(tmem);
    nix_parser::collect_transitive_bindings(ast, "deps", &bindings);

    test::@check(bindings.size == 1);
    if (bindings.size >= 1) {
      usz idx;
      if (try i = bindings[0].index_of("foo = ")) {
        idx = i;
      } else {
        idx = usz.max;
      }
      test::@check(idx != usz.max);
    }
  };
}

fn void test_transitive_bindings_recursive() @test {
  @pool() {
    String source = `
{
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        bar = "bar";
        foo = pkgs.writeText "foo" bar;
        deps = with pkgs; [ gcc foo ];
      in {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* ast = nix_parser::tr_source(root, &source)!!;

    List{String} bindings;
    bindings.init(tmem);
    nix_parser::collect_transitive_bindings(ast, "deps", &bindings);

    test::@check(bindings.size == 2);
    bool found_bar = false;
    bool found_foo = false;
    foreach (String b : bindings) {
      if (try b.index_of("bar = ")) found_bar = true;
      if (try b.index_of("foo = ")) found_foo = true;
    }
    test::@check(found_bar);
    test::@check(found_foo);
  };
}

fn void test_transitive_bindings_none() @test {
  @pool() {
    String source = `
{
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        deps = with pkgs; [ gcc go ];
      in {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* ast = nix_parser::tr_source(root, &source)!!;

    List{String} bindings;
    bindings.init(tmem);
    nix_parser::collect_transitive_bindings(ast, "deps", &bindings);

    test::@check(bindings.size == 0);
  };
}

fn void test_extract_mkshell_env_present() @test {
  @pool() {
    String source = `
{
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        deps = with pkgs; [ gcc ];
      in {
        packages.dev-shell = dev-shell.mkShell {
          inherit pkgs deps;
          env = {
            FOO = "bar";
            BAZ = "${pkgs.hello}/bin/hello";
          };
        };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);

    String env_block = nix_parser::extract_mkshell_env_raw(root, &source);

    test::@check(env_block.len > 0);
    bool has_env = false;
    if (try env_block.index_of("env = ")) has_env = true;
    test::@check(has_env);
    bool has_foo = false;
    if (try env_block.index_of("FOO")) has_foo = true;
    test::@check(has_foo);
    bool has_baz = false;
    if (try env_block.index_of("BAZ")) has_baz = true;
    test::@check(has_baz);
  };
}

fn void test_extract_mkshell_env_absent() @test {
  @pool() {
    String source = `
{
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        deps = with pkgs; [ gcc ];
      in {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs deps; };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);

    String env_block = nix_parser::extract_mkshell_env_raw(root, &source);

    test::@check(env_block.len == 0);
  };
}

fn void test_extract_mkshell_env_no_mkshell() @test {
  @pool() {
    String source = `
{
  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { inherit system; };
    in {
      packages.default = pkgs.hello;
    };
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);

    String env_block = nix_parser::extract_mkshell_env_raw(root, &source);

    test::@check(env_block.len == 0);
  };
}

fn void test_string_interpolation_simple() @test {
  @pool() {
    String source = `{ program = "${self.packages.sf-acp}/bin/sf-acp"; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{ program = "${self.packages.sf-acp}/bin/sf-acp"; }`);
  };
}

fn void test_string_interpolation_nested_select() @test {
  @pool() {
    String source = `{ program = "${self.packages.${system}.sf-acp}/bin/sf-acp"; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{ program = "${self.packages.${system}.sf-acp}/bin/sf-acp"; }`);
  };
}

fn void test_string_interpolation_multiple() @test {
  @pool() {
    String source = `{ x = "${foo}/bin/${bar}/lib"; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::eq(nix_code_str, `{ x = "${foo}/bin/${bar}/lib"; }`);
  };
}

fn void test_indented_string_interpolation() @test {
  @pool() {
    String source = `{ hook = ''
      export PATH="${pkgs.hello}/bin:$PATH"
      echo "${greeting}"
    ''; }`;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    test::@check(test_utils::string_contains(nix_code_str, "${pkgs.hello}"));
    test::@check(test_utils::string_contains(nix_code_str, "${greeting}"));
    test::@check(!test_utils::string_contains(nix_code_str, "${...}"));
  };
}

fn void test_flake_apps_interpolation_roundtrip() @test {
  @pool() {
    String source = `
{
  description = "sf-acp";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    dev-shell.url = "github:peinz/dev-shell";
  };
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        deps = with pkgs; [ cargo rustc ];
      in
      {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        packages.sf-acp = pkgs.hello;
        apps.sf-acp = {
          type = "app";
          program = "${self.packages.${system}.sf-acp}/bin/sf-acp";
        };
      }
    );
}
    `;
    TsTree* tree = nix_parser::parse_ts_nix_tree(source);
    defer ts::tree_delete(tree);
    TsNode root = ts::tree_root_node(tree);
    Expression* expr = nix_parser::tr_source(root, &source)!!;
    String nix_code_str = nix_parser::serialize_code(expr);
    // The interpolation must be preserved exactly, not replaced with ${...}
    test::@check(test_utils::string_contains(nix_code_str, "${self.packages.${system}.sf-acp}"));
    test::@check(!test_utils::string_contains(nix_code_str, "${...}"));
  };
}

fn void test_apps_filtered_out() @test {
  @pool() {
    String source = `
{
  description = "sf-acp";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    flake-utils.url = "github:numtide/flake-utils";
    dev-shell.url = "github:peinz/dev-shell";
  };
  outputs = { self, nixpkgs, flake-utils, dev-shell }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        deps = with pkgs; [ cargo rustc ];
      in
      {
        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };
        packages.sf-acp = pkgs.hello;
        devShells.default = pkgs.mkShell { buildInputs = deps; };
        apps.sf-acp = {
          type = "app";
          program = "${self.packages.${system}.sf-acp}/bin/sf-acp";
        };
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
    // packages.dev-shell must survive
    test::@check(test_utils::string_contains(nix_code_str, "packages.dev-shell"));
    // apps.sf-acp must be filtered out
    test::@check(!test_utils::string_contains(nix_code_str, "apps.sf-acp"));
    // devShells.default must be filtered out
    test::@check(!test_utils::string_contains(nix_code_str, "devShells.default"));
    // packages.sf-acp must be filtered out
    test::@check(!test_utils::string_contains(nix_code_str, "packages.sf-acp"));
  };
}
