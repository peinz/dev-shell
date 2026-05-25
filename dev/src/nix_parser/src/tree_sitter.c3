// FFI declarations for tree-sitter C API

module ts;

import std::io;

// Tree-sitter types - using simple definitions
alias TsStateId = ushort;
alias TsSymbol = ushort;
alias TsFieldId = ushort;
alias TsLanguage = void;
alias TsParser = void;
alias TsTree = void;
alias TsQuery = void;
alias TsQueryCursor = void;

// Position in source - matches C TSPoint exactly
// C: uint32_t row; uint32_t column; (8 bytes total)
struct TsPoint {
  uint row;      // offset 0, size 4
  uint column;   // offset 4, size 4
}

// Node structure - matches C TsNode exactly (32 bytes on 64-bit)
// C: uint32_t context[4]; const void *id; const TSTree *tree;
// Layout: context[16 bytes] + padding[8 bytes] + id[8 bytes] + tree[8 bytes] = 40? 
// But sizeof says 32, so let's see...
// Actually on 64-bit: context[16] + id[8] + tree[8] = 32 with natural alignment
struct TsNode {
  uint[4] context;   // offset 0, size 16
  void* id;          // offset 16, size 8
  TsTree* tree;      // offset 24, size 8
                     // Total: 32 bytes
}

// Tree cursor for traversal - matches C TSTreeCursor exactly (32 bytes on 64-bit)
// C: const void *tree; const void *id; uint32_t context[3];
// Layout: tree[8] + id[8] + context[12] + padding[4] = 32
struct TsTreeCursor {
  void* tree;         // offset 0, size 8
  void* id;           // offset 8, size 8
  uint[3] context;    // offset 16, size 12
                      // Total: 32 bytes
}

// Input encoding
enum TsInputEncoding : uint {
  TS_INPUT_ENCODING_UTF8,
  TS_INPUT_ENCODING_UTF16LE,
  TS_INPUT_ENCODING_UTF16BE,
  TS_INPUT_ENCODING_CUSTOM
}

// Symbol type
enum TsSymbolType : uint {
  TS_SYMBOL_TYPE_REGULAR,
  TS_SYMBOL_TYPE_ANONYMOUS,
  TS_SYMBOL_TYPE_SUPERTYPE,
  TS_SYMBOL_TYPE_AUXILIARY
}

// Parse state
struct TsParseState {
  void* payload;
  uint current_byte_offset;
  bool has_error;
}

// Parser options
struct TsParseOptions {
  bool new_parse;
  TsParseState* state;
}

// =====================
// Foreign function declarations
// =====================

// Parser lifecycle
extern fn TsParser* parser_new() @cname("ts_parser_new");
extern fn void parser_delete(TsParser* parser) @cname("ts_parser_delete");
extern fn bool parser_set_language(TsParser* parser, TsLanguage* language) @cname("ts_parser_set_language");
extern fn TsLanguage* parser_language(TsParser* parser) @cname("ts_parser_language");

// Parsing
extern fn TsTree* parser_parse_string(
    TsParser* parser,
    TsTree* old_tree,
    char* string,
    uint length
    ) @cname("ts_parser_parse_string");

// Tree operations
extern fn void tree_delete(TsTree* tree) @cname("ts_tree_delete");
extern fn TsNode tree_root_node(TsTree* tree) @cname("ts_tree_root_node");
extern fn TsLanguage* tree_language(TsTree* tree) @cname("ts_tree_language");
extern fn void tree_edit(TsTree* tree, void* edit) @cname("ts_tree_edit");

// Node operations
extern fn TsNode node_child(TsNode node, uint index) @cname("ts_node_child");
extern fn TsNode node_named_child(TsNode node, uint index) @cname("ts_node_named_child");
extern fn uint node_child_count(TsNode node) @cname("ts_node_child_count");
extern fn uint node_named_child_count(TsNode node) @cname("ts_node_named_child_count");
extern fn TsNode node_parent(TsNode node) @cname("ts_node_parent");
extern fn TsNode node_next_sibling(TsNode node) @cname("ts_node_next_sibling");
extern fn TsNode node_prev_sibling(TsNode node) @cname("ts_node_prev_sibling");
extern fn TsNode node_next_named_sibling(TsNode node) @cname("ts_node_next_named_sibling");
extern fn TsNode node_prev_named_sibling(TsNode node) @cname("ts_node_prev_named_sibling");

extern fn bool node_is_null(TsNode node) @cname("ts_node_is_null");
extern fn bool node_is_named(TsNode node) @cname("ts_node_is_named");
extern fn bool node_is_missing(TsNode node) @cname("ts_node_is_missing");
extern fn bool node_is_extra(TsNode node) @cname("ts_node_is_extra");
extern fn bool node_has_changes(TsNode node) @cname("ts_node_has_changes");
extern fn bool node_has_error(TsNode node) @cname("ts_node_has_error");

extern fn TsNode _node_child_by_field_name(
    TsNode node,
    char* name,
    uint name_length
    ) @cname("ts_node_child_by_field_name");
fn TsNode node_child_by_field_name(TsNode node, String name) {
  return _node_child_by_field_name(node, name.ptr, name.len);
}

// Node type and text
extern fn ZString node_type(TsNode node) @cname("ts_node_type");
extern fn TsSymbol node_symbol(TsNode node) @cname("ts_node_symbol");
extern fn ZString node_string(TsNode node) @cname("ts_node_string");

// Source location
extern fn uint node_start_byte(TsNode node) @cname("ts_node_start_byte");
extern fn uint node_end_byte(TsNode node) @cname("ts_node_end_byte");
extern fn TsPoint node_start_point(TsNode node) @cname("ts_node_start_point");
extern fn TsPoint node_end_point(TsNode node) @cname("ts_node_end_point");

// Tree cursor
extern fn TsTreeCursor tree_cursor_new(TsNode node) @cname("ts_tree_cursor_new");
extern fn void tree_cursor_delete(TsTreeCursor* cursor) @cname("ts_tree_cursor_delete");

// Helper to create a null node
fn TsNode node_null() {
  TsNode null_node = {
    .context = {0, 0, 0, 0},
    .id = null,
    .tree = null
  };
  return null_node;
}
extern fn bool tree_cursor_goto_first_child(TsTreeCursor* cursor) @cname("ts_tree_cursor_goto_first_child");
extern fn bool tree_cursor_goto_next_sibling(TsTreeCursor* cursor) @cname("ts_tree_cursor_goto_next_sibling");
extern fn bool tree_cursor_goto_parent(TsTreeCursor* cursor) @cname("ts_tree_cursor_goto_parent");
extern fn TsNode tree_cursor_current_node(TsTreeCursor* cursor) @cname("ts_tree_cursor_current_node");
extern fn ZString tree_cursor_current_field_name(TsTreeCursor* cursor) @cname("ts_tree_cursor_current_field_name");

// Language operations
extern fn uint language_version(TsLanguage* language) @cname("ts_language_version");
extern fn uint language_symbol_count(TsLanguage* language) @cname("ts_language_symbol_count");
extern fn uint language_state_count(TsLanguage* language) @cname("ts_language_state_count");
extern fn ZString language_symbol_name(TsLanguage* language, TsSymbol symbol) @cname("ts_language_symbol_name");
extern fn TsSymbolType language_symbol_type(TsLanguage* language, TsSymbol symbol) @cname("ts_language_symbol_type");
