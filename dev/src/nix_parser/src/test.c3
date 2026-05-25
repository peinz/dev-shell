module main;

import std;
import nix_parser;
import ts;

// fn void main() {
//   String source = `with pkgs; [ gcc go ]`;
//   
//   io::printn("------ ts ast --------");
//   TsTree* tree = nix_parser::parse_ts_nix_tree(source);
//   TsNode root = ts::tree_root_node(tree);
//   ts::print_syntax_tree(root);
// }
