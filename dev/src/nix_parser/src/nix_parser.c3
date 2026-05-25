// Nix parser module with AST-based extraction functions

module nix_parser;

import std::io;
import std::io::file;
import std::collections::list;
import libc;
import ts;


// [tree-sitter-nix]
extern fn TsLanguage* tree_sitter_nix();

// TODO: Add error handling
fn TsTree* parse_ts_nix_tree(String source) {
  TsParser* parser = ts::parser_new();
  if (parser == null) return null;

  if (!ts::parser_set_language(parser, tree_sitter_nix())) {
    ts::parser_delete(parser);
    return null;
  }

  ZString source_ptr = source.zstr_copy(tmem);
  TsTree* ts_tree = ts::parser_parse_string(parser, null, source_ptr, (uint)source.len);
  ts::parser_delete(parser);

  if (ts_tree == null) {
    return null;
  }

  return ts_tree;
}


// [types]
enum ExpressionType : int {
  ATTRSET,
  BINDING,
  BINARY,
  INTEGER,
  STRING,
  VARIABLE,
  SELECT,
  LIST,
  FUNCTION,
  APPLY,
  LET,
  WITH,
  INHERIT,
  FORMAL,
  FORMALS,
  PAREN,
}

union Expression {
  BaseExpression as_base_expression;
  AttrsetExpression as_attrset_expression;
  BindingExpression as_binding_expression;
  BinaryExpression as_binary_expression;
  IntegerExpression as_integer_expression;
  StringExpression as_string_expression;
  VariableExpression as_variable_expression;
  SelectExpression as_select_expression;
  ListExpression as_list_expression;
  FunctionExpression as_function_expression;
  ApplyExpression as_apply_expression;
  LetExpression as_let_expression;
  WithExpression as_with_expression;
  InheritExpression as_inherit_expression;
  FormalExpression as_formal_expression;
  FormalsExpression as_formals_expression;
  ParenExpression as_paren_expression;
}

struct BaseExpression {
  ExpressionType type;
}

struct AttrsetExpression {
  ExpressionType type;
  List{BindingExpression*} bindings;
  bool multiline;
  bool is_rec;
  bool is_let;
}

struct BindingExpression {
  ExpressionType type;
  String indentifier;
  Expression* expression;
}

struct BinaryExpression {
  ExpressionType type;
  String operator;
  Expression* left;
  Expression* right;
}

struct IntegerExpression {
  ExpressionType type;
  String value;
}

struct StringExpression {
  ExpressionType type;
  String value;
}

struct VariableExpression {
  ExpressionType type;
  String name;
}

struct SelectExpression {
  ExpressionType type;
  Expression* expression;
  String attrpath;  // simplified: just store the full path as string
}

struct ListExpression {
  ExpressionType type;
  List{Expression*} elements;
  bool multiline;
}

struct FunctionExpression {
  ExpressionType type;
  FormalsExpression* formals;
  Expression* body;
}

struct ApplyExpression {
  ExpressionType type;
  Expression* function;
  Expression* argument;
}

struct LetExpression {
  ExpressionType type;
  List{BindingExpression*} bindings;
  Expression* body;
  bool multiline;
}

struct WithExpression {
  ExpressionType type;
  Expression* expression;
  Expression* body;
}

struct InheritExpression {
  ExpressionType type;
  List{String} names;
}

struct ParenExpression {
  ExpressionType type;
  Expression* expression;
}

struct FormalExpression {
  ExpressionType type;
  String name;
  Expression* default_value; // optional
}

struct FormalsExpression {
  ExpressionType type;
  List{FormalExpression*} formals;
}

faultdef PARSE_ERROR;

// [translate tree-sitter nodes to NixAst]
fn Expression*? tr_source(TsNode node, String* source) {
  ZString node_type = ts::node_type(node);
  if (node_type != "source_code") return PARSE_ERROR~;
  TsNode expression = ts::node_child_by_field_name(node, "expression");
  // if (!expression) return PARSE_ERROR~;
  return tr_expression(expression, source);
}

fn Expression*? tr_expression(TsNode node, String* source) {
  ZString node_type = ts::node_type(node);
  if (node_type == "attrset_expression") return (Expression*)tr_attrset_expression(node, source);
  if (node_type == "rec_attrset_expression") return (Expression*)tr_rec_attrset_expression(node, source);
  if (node_type == "let_attrset_expression") return (Expression*)tr_let_attrset_expression(node, source);
  if (node_type == "binding_set") return (Expression*)tr_binding_expression(node, source);
  if (node_type == "binding") return (Expression*)tr_binding_expression(node, source);
  if (node_type == "binary_expression") return (Expression*)tr_binary_expression(node, source);
  if (node_type == "integer_expression") return (Expression*)tr_integer_expression(node, source);
  if (node_type == "string_expression") return (Expression*)tr_string_expression(node, source);
  if (node_type == "variable_expression") return (Expression*)tr_variable_expression(node, source);
  if (node_type == "select_expression") return (Expression*)tr_select_expression(node, source);
  if (node_type == "list_expression") return (Expression*)tr_list_expression(node, source);
  if (node_type == "function_expression") return (Expression*)tr_function_expression(node, source);
  if (node_type == "apply_expression") return (Expression*)tr_apply_expression(node, source);
  if (node_type == "let_expression") return (Expression*)tr_let_expression(node, source);
  if (node_type == "with_expression") return (Expression*)tr_with_expression(node, source);
  if (node_type == "inherit") return (Expression*)tr_inherit_expression(node, source);
  if (node_type == "formals") return (Expression*)tr_formals_expression(node, source);
  if (node_type == "formal") return (Expression*)tr_formal_expression(node, source);
  if (node_type == "parenthesized_expression") return (Expression*)tr_paren_expression(node, source);
  return PARSE_ERROR~;
}

fn bool is_attrset_multiline(TsNode node) {
  // Returns true if '{' and '}' are on different lines (multiline)
  // Find the '{' and '}' tokens (anonymous children)
  TsPoint open_brace_point;
  TsPoint close_brace_point;
  bool found_open = false;
  bool found_close = false;
  
  int child_count = ts::node_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode child = ts::node_child(node, i);
    ZString child_type = ts::node_type(child);
    
    if (child_type == "{") {
      open_brace_point = ts::node_start_point(child);
      found_open = true;
    } else if (child_type == "}") {
      close_brace_point = ts::node_start_point(child);
      found_close = true;
    }
  }
  
  // If we found both braces, compare their line numbers
  if (found_open && found_close) {
    return open_brace_point.row != close_brace_point.row;
  }
  
  // Default to multi-line if we can't determine
  return false;
}

fn bool is_let_multiline(TsNode node) {
  // Find the 'let' and 'in' tokens (anonymous children)
  TsPoint let_point;
  TsPoint in_point;
  bool found_let = false;
  bool found_in = false;
  
  int child_count = ts::node_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode child = ts::node_child(node, i);
    ZString child_type = ts::node_type(child);
    
    if (child_type == "let") {
      let_point = ts::node_start_point(child);
      found_let = true;
    } else if (child_type == "in") {
      in_point = ts::node_start_point(child);
      found_in = true;
    }
  }
  
  // If we found both keywords, compare their line numbers
  if (found_let && found_in) {
    return let_point.row != in_point.row;
  }

  // Default to multi-line if we can't determine
  return false;
}

fn bool is_list_multiline(TsNode node) {
  // Find the '[' and ']' tokens (anonymous children)
  TsPoint open_bracket_point;
  TsPoint close_bracket_point;
  bool found_open = false;
  bool found_close = false;

  int child_count = ts::node_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode child = ts::node_child(node, i);
    ZString child_type = ts::node_type(child);

    if (child_type == "[") {
      open_bracket_point = ts::node_start_point(child);
      found_open = true;
    } else if (child_type == "]") {
      close_bracket_point = ts::node_start_point(child);
      found_close = true;
    }
  }

  // If we found both brackets, compare their line numbers
  if (found_open && found_close) {
    return open_bracket_point.row != close_bracket_point.row;
  }

  // Default to multi-line if we can't determine
  return false;
}

fn AttrsetExpression* tr_attrset_expression(TsNode node, String* source) {
  AttrsetExpression* expr = mem::tnew(AttrsetExpression, { .type = ATTRSET, .is_rec = false, .is_let = false });

  int child_count = ts::node_named_child_count(node);
  if (child_count > 0) {
    TsNode binding_set = ts::node_named_child(node, 0);
    ZString binding_set_type = ts::node_type(binding_set);
    
    if (binding_set_type == "binding_set") {
      // Process each binding in the binding set
      int binding_count = ts::node_named_child_count(binding_set);
      for (int i = 0; i < binding_count; i++) {
        TsNode binding_node = ts::node_named_child(binding_set, i);
        ZString binding_type = ts::node_type(binding_node);
        if (binding_type == "binding") {
          BindingExpression* binding = tr_binding_expression(binding_node, source);
          expr.bindings.push(binding);
        } else if (binding_type == "inherit") {
          InheritExpression* inherit = tr_inherit_expression(binding_node, source);
          // Wrap inherit in a binding expression for uniform handling
          BindingExpression* binding_wrapper = mem::tnew(BindingExpression, {
            .type = BINDING,
            .indentifier = "inherit",
            .expression = (Expression*)inherit
          });
          expr.bindings.push(binding_wrapper);
        }
      }
    }
  }

  expr.multiline = is_attrset_multiline(node);
  return expr;
}

fn AttrsetExpression* tr_rec_attrset_expression(TsNode node, String* source) {
  AttrsetExpression* expr = mem::tnew(AttrsetExpression, { .type = ATTRSET, .is_rec = true, .is_let = false });

  int child_count = ts::node_named_child_count(node);
  if (child_count > 0) {
    TsNode binding_set = ts::node_named_child(node, 0);
    ZString binding_set_type = ts::node_type(binding_set);
    
    if (binding_set_type == "binding_set") {
      // Process each binding in the binding set
      int binding_count = ts::node_named_child_count(binding_set);
      for (int i = 0; i < binding_count; i++) {
        TsNode binding_node = ts::node_named_child(binding_set, i);
        ZString binding_type = ts::node_type(binding_node);
        if (binding_type == "binding") {
          BindingExpression* binding = tr_binding_expression(binding_node, source);
          expr.bindings.push(binding);
        } else if (binding_type == "inherit") {
          InheritExpression* inherit = tr_inherit_expression(binding_node, source);
          BindingExpression* binding_wrapper = mem::tnew(BindingExpression, {
            .type = BINDING,
            .indentifier = "inherit",
            .expression = (Expression*)inherit
          });
          expr.bindings.push(binding_wrapper);
        }
      }
    }
  }

  expr.multiline = is_attrset_multiline(node);
  return expr;
}

fn AttrsetExpression* tr_let_attrset_expression(TsNode node, String* source) {
  AttrsetExpression* expr = mem::tnew(AttrsetExpression, { .type = ATTRSET, .is_rec = false, .is_let = true });

  int child_count = ts::node_named_child_count(node);
  if (child_count > 0) {
    TsNode binding_set = ts::node_named_child(node, 0);
    ZString binding_set_type = ts::node_type(binding_set);
    
    if (binding_set_type == "binding_set") {
      // Process each binding in the binding set
      int binding_count = ts::node_named_child_count(binding_set);
      for (int i = 0; i < binding_count; i++) {
        TsNode binding_node = ts::node_named_child(binding_set, i);
        ZString binding_type = ts::node_type(binding_node);
        if (binding_type == "binding") {
          BindingExpression* binding = tr_binding_expression(binding_node, source);
          expr.bindings.push(binding);
        } else if (binding_type == "inherit") {
          InheritExpression* inherit = tr_inherit_expression(binding_node, source);
          BindingExpression* binding_wrapper = mem::tnew(BindingExpression, {
            .type = BINDING,
            .indentifier = "inherit",
            .expression = (Expression*)inherit
          });
          expr.bindings.push(binding_wrapper);
        }
      }
    }
  }

  expr.multiline = is_attrset_multiline(node);
  return expr;
}

fn BindingExpression* tr_binding_expression(TsNode node, String* source) {
  BindingExpression* expr = mem::tnew(BindingExpression, { .type = BINDING });

  TsNode binding_node = node; 
  TsNode attrpath = ts::node_child_by_field_name(binding_node, "attrpath");
  
  // Build the full attrpath as a string (e.g., "nixpkgs.url" or "outputs")
  DString attrpath_str = dstring::new(tmem, "");
  int attr_count = ts::node_named_child_count(attrpath);
  for (int i = 0; i < attr_count; i++) {
    TsNode attr_node = ts::node_named_child(attrpath, i);
    ZString attr_type = ts::node_type(attr_node);
    if (attr_type == "identifier") {
      String text = ts::node_get_text(attr_node, source);
      if (i > 0) attrpath_str.append_char('.');
      attrpath_str.append_string(text);
    }
  }
  expr.indentifier = attrpath_str.str_view();

  TsNode rhs_expr = ts::node_child_by_field_name(binding_node, "expression");
  expr.expression = tr_expression(rhs_expr, source)!!;
  return expr;
}

fn BinaryExpression* tr_binary_expression(TsNode node, String* source) {
  BinaryExpression* expr = mem::tnew(BinaryExpression, { .type = BINARY });
  
  // Get the operator token text
  TsNode op_node = ts::node_child_by_field_name(node, "operator");
  expr.operator = ts::node_get_text(op_node, source);
  
  // Recursively parse left and right
  TsNode left_node = ts::node_child_by_field_name(node, "left");
  TsNode right_node = ts::node_child_by_field_name(node, "right");
  
  expr.left = tr_expression(left_node, source)!!;
  expr.right = tr_expression(right_node, source)!!;

  return expr;
}

fn IntegerExpression* tr_integer_expression(TsNode node, String* source) {
  IntegerExpression* expr = mem::tnew(IntegerExpression, { .type = INTEGER });
  expr.value = ts::node_get_text(node, source);
  return expr;
}

fn StringExpression* tr_string_expression(TsNode node, String* source) {
  StringExpression* expr = mem::tnew(StringExpression, { .type = STRING });
  
  // Get the string content (skip the quotes)
  // The string_expression contains: ", string_fragment(s), "
  DString value_str = dstring::new(tmem, "");
  int child_count = ts::node_named_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode child = ts::node_named_child(node, i);
    ZString child_type = ts::node_type(child);
    if (child_type == "string_fragment") {
      value_str.append_string(ts::node_get_text(child, source));
    } else if (child_type == "interpolation") {
      // For interpolation ${...}, we'll include a placeholder
      value_str.append_string("${...}");
    }
  }
  expr.value = value_str.str_view();
  return expr;
}

fn VariableExpression* tr_variable_expression(TsNode node, String* source) {
  VariableExpression* expr = mem::tnew(VariableExpression, { .type = VARIABLE });
  TsNode name_node = ts::node_child_by_field_name(node, "name");
  expr.name = ts::node_get_text(name_node, source);
  return expr;
}

fn SelectExpression* tr_select_expression(TsNode node, String* source) {
  SelectExpression* expr = mem::tnew(SelectExpression, { .type = SELECT });
  
  TsNode base_expr = ts::node_child_by_field_name(node, "expression");
  expr.expression = tr_expression(base_expr, source)!!;
  
  // Build the attrpath string
  TsNode attrpath_node = ts::node_child_by_field_name(node, "attrpath");
  DString path_str = dstring::new(tmem, "");
  int attr_count = ts::node_named_child_count(attrpath_node);
  bool first = true;
  for (int i = 0; i < attr_count; i++) {
    TsNode attr_node = ts::node_named_child(attrpath_node, i);
    ZString attr_type = ts::node_type(attr_node);
    if (attr_type == "identifier") {
      String text = ts::node_get_text(attr_node, source);
      if (!first) path_str.append_char('.');
      first = false;
      path_str.append_string(text);
    } else if (attr_type == "interpolation" || attr_type == "string_interpolation") {
      // Handle ${...} interpolation - extract the inner expression text
      if (!first) path_str.append_char('.');
      first = false;
      // Get the inner expression from the interpolation
      TsNode interp_expr = ts::node_child_by_field_name(attr_node, "expression");
      if (!ts::node_is_null(interp_expr)) {
        String expr_text = ts::node_get_text(interp_expr, source);
        path_str.append_string("${");
        path_str.append_string(expr_text);
        path_str.append_char('}');
      } else {
        path_str.append_string("${...}");
      }
    }
  }
  expr.attrpath = path_str.str_view();
  
  return expr;
}

fn ListExpression* tr_list_expression(TsNode node, String* source) {
  ListExpression* expr = mem::tnew(ListExpression, { .type = LIST });

  int child_count = ts::node_named_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode element = ts::node_named_child(node, i);
    ZString element_type = ts::node_type(element);
    if (element_type == "element") {
      TsNode actual_expr = ts::node_named_child(element, 0);
      Expression* elem_expr = tr_expression(actual_expr, source)!!;
      expr.elements.push(elem_expr);
    } else {
      // Direct expression node
      Expression* elem_expr = tr_expression(element, source)!!;
      expr.elements.push(elem_expr);
    }
  }

  expr.multiline = is_list_multiline(node);
  return expr;
}

fn FunctionExpression* tr_function_expression(TsNode node, String* source) {
  FunctionExpression* expr = mem::tnew(FunctionExpression, { .type = FUNCTION });
  
  // Function can have formals (structured params like { a, b }) or universal (single param like a:)
  TsNode formals_node = ts::node_child_by_field_name(node, "formals");
  if (!ts::node_is_null(formals_node)) {
    expr.formals = tr_formals_expression(formals_node, source);
  } else {
    // Check for universal pattern (e.g., "system:" instead of "{ system }:")
    TsNode universal_node = ts::node_child_by_field_name(node, "universal");
    if (!ts::node_is_null(universal_node)) {
      // Create a single formal from the universal identifier
      FormalsExpression* formals = mem::tnew(FormalsExpression, { .type = FORMALS });
      FormalExpression* formal = mem::tnew(FormalExpression, { 
        .type = FORMAL,
        .name = ts::node_get_text(universal_node, source)
      });
      formals.formals.push(formal);
      expr.formals = formals;
    }
  }
  
  TsNode body_node = ts::node_child_by_field_name(node, "body");
  if (ts::node_is_null(body_node)) {
    // Sometimes body is not a named field, look for the last expression child
    int child_count = ts::node_named_child_count(node);
    if (child_count > 0) {
      body_node = ts::node_named_child(node, child_count - 1);
    }
  }
  if (!ts::node_is_null(body_node)) {
    expr.body = tr_expression(body_node, source)!!;
  }
  
  return expr;
}

fn ApplyExpression* tr_apply_expression(TsNode node, String* source) {
  ApplyExpression* expr = mem::tnew(ApplyExpression, { .type = APPLY });
  
  TsNode func_node = ts::node_child_by_field_name(node, "function");
  TsNode arg_node = ts::node_child_by_field_name(node, "argument");
  
  expr.function = tr_expression(func_node, source)!!;
  expr.argument = tr_expression(arg_node, source)!!;
  
  return expr;
}

fn LetExpression* tr_let_expression(TsNode node, String* source) {
  LetExpression* expr = mem::tnew(LetExpression, { .type = LET });
  
  // Find binding_set
  TsNode binding_set = ts::node_null();
  int child_count = ts::node_named_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode child = ts::node_named_child(node, i);
    ZString child_type = ts::node_type(child);
    if (child_type == "binding_set") {
      binding_set = child;
      break;
    }
  }
  
  if (!ts::node_is_null(binding_set)) {
    int binding_count = ts::node_named_child_count(binding_set);
    for (int i = 0; i < binding_count; i++) {
      TsNode binding_node = ts::node_named_child(binding_set, i);
      ZString binding_type = ts::node_type(binding_node);
      if (binding_type == "binding") {
        BindingExpression* binding = tr_binding_expression(binding_node, source);
        expr.bindings.push(binding);
      }
    }
  }
  
  // Find body
  TsNode body_node = ts::node_child_by_field_name(node, "body");
  if (!ts::node_is_null(body_node)) {
    expr.body = tr_expression(body_node, source)!!;
  }
  
  expr.multiline = is_let_multiline(node);
  return expr;
}

fn WithExpression* tr_with_expression(TsNode node, String* source) {
  WithExpression* expr = mem::tnew(WithExpression, { .type = WITH });
  
  TsNode with_expr = ts::node_child_by_field_name(node, "environment");
  if (!ts::node_is_null(with_expr)) {
    expr.expression = tr_expression(with_expr, source)!!;
  }
  
  TsNode body_node = ts::node_child_by_field_name(node, "body");
  if (!ts::node_is_null(body_node)) {
    expr.body = tr_expression(body_node, source)!!;
  }
  
  return expr;
}

fn InheritExpression* tr_inherit_expression(TsNode node, String* source) {
  InheritExpression* expr = mem::tnew(InheritExpression, { .type = INHERIT });
  
  // Inherit has "inherited_attrs" child containing the names
  int child_count = ts::node_named_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode child = ts::node_named_child(node, i);
    ZString child_type = ts::node_type(child);
    if (child_type == "inherited_attrs") {
      // Process each attr in inherited_attrs
      int attr_count = ts::node_named_child_count(child);
      for (int j = 0; j < attr_count; j++) {
        TsNode attr = ts::node_named_child(child, j);
        ZString attr_type = ts::node_type(attr);
        if (attr_type == "identifier") {
          expr.names.push(ts::node_get_text(attr, source));
        }
      }
    } else if (child_type == "attrpath") {
      // Fallback: Get the identifier from attrpath
      int attr_count = ts::node_named_child_count(child);
      for (int j = 0; j < attr_count; j++) {
        TsNode attr = ts::node_named_child(child, j);
        ZString attr_type = ts::node_type(attr);
        if (attr_type == "identifier") {
          expr.names.push(ts::node_get_text(attr, source));
        }
      }
    }
  }
  
  return expr;
}

fn FormalsExpression* tr_formals_expression(TsNode node, String* source) {
  FormalsExpression* expr = mem::tnew(FormalsExpression, { .type = FORMALS });
  
  int child_count = ts::node_named_child_count(node);
  for (int i = 0; i < child_count; i++) {
    TsNode child = ts::node_named_child(node, i);
    ZString child_type = ts::node_type(child);
    if (child_type == "formal") {
      FormalExpression* formal = tr_formal_expression(child, source);
      expr.formals.push(formal);
    }
  }
  
  return expr;
}

fn FormalExpression* tr_formal_expression(TsNode node, String* source) {
  FormalExpression* expr = mem::tnew(FormalExpression, { .type = FORMAL });
  
  TsNode name_node = ts::node_child_by_field_name(node, "name");
  if (!ts::node_is_null(name_node)) {
    expr.name = ts::node_get_text(name_node, source);
  }
  
  // Check for default value
  TsNode default_node = ts::node_child_by_field_name(node, "default");
  if (!ts::node_is_null(default_node)) {
    expr.default_value = tr_expression(default_node, source)!!;
  }

  return expr;
}

fn ParenExpression* tr_paren_expression(TsNode node, String* source) {
  ParenExpression* expr = mem::tnew(ParenExpression, { .type = PAREN });

  // Get the inner expression from the parenthesized expression
  TsNode inner = ts::node_child_by_field_name(node, "expression");
  if (ts::node_is_null(inner)) {
    // Try to find the first named child that's an expression
    int child_count = ts::node_named_child_count(node);
    for (int i = 0; i < child_count; i++) {
      TsNode child = ts::node_named_child(node, i);
      ZString child_type = ts::node_type(child);
      if (child_type != "identifier") {
        inner = child;
        break;
      }
    }
  }

  if (!ts::node_is_null(inner)) {
    expr.expression = tr_expression(inner, source)!!;
  }

  return expr;
}


// [serialization tree]
fn void _serialize_tree(Expression* expr, DString* out, int depth = 0) {
  if (!expr) return;

  for (int i = 0; i < depth; i++) {
    out.append_string(" ");
  }

  switch (expr.as_base_expression.type) {
    case ATTRSET:
      DString attrset_info = dstring::new(tmem, "attrset(");
      if (expr.as_attrset_expression.is_rec) {
        attrset_info.append_string("rec=true, ");
      }
      if (expr.as_attrset_expression.is_let) {
        attrset_info.append_string("let=true, ");
      }
      attrset_info.append_string("multiline=");
      attrset_info.append_string(expr.as_attrset_expression.multiline ? "true" : "false");
      attrset_info.append_string("):\n");
      out.append_string(attrset_info.str_view());
      foreach (BindingExpression* binding : expr.as_attrset_expression.bindings) {
        _serialize_tree((Expression*)binding, out, depth + 1);
      }
    case BINDING:
      String txt = string::format(tmem, "binding(%s):\n", expr.as_binding_expression.indentifier);
      out.append_string(txt);
      _serialize_tree(expr.as_binding_expression.expression, out, depth + 1);
    case BINARY:
      String txt = string::format(tmem, "binop(%s):\n", expr.as_binary_expression.operator);
      out.append_string(txt);
      _serialize_tree(expr.as_binary_expression.left, out, depth + 1);
      _serialize_tree(expr.as_binary_expression.right, out, depth + 1);
    case INTEGER:
      String txt = string::format(tmem, "int(%s)\n", expr.as_integer_expression.value);
      out.append_string(txt);
    case STRING:
      String str_txt = string::format(tmem, "string(%s)\n", expr.as_string_expression.value);
      out.append_string(str_txt);
    case VARIABLE:
      String var_txt = string::format(tmem, "var(%s)\n", expr.as_variable_expression.name);
      out.append_string(var_txt);
    case SELECT:
      String sel_txt = string::format(tmem, "select(%s):\n", expr.as_select_expression.attrpath);
      out.append_string(sel_txt);
      _serialize_tree(expr.as_select_expression.expression, out, depth + 1);
    case LIST:
      String list_txt = string::format(tmem, "list(multiline=%s):\n", expr.as_list_expression.multiline ? "true" : "false");
      out.append_string(list_txt);
      foreach (Expression* elem : expr.as_list_expression.elements) {
        _serialize_tree(elem, out, depth + 1);
      }
    case FUNCTION:
      out.append_string("function:\n");
      _serialize_tree((Expression*)expr.as_function_expression.formals, out, depth + 1);
      _serialize_tree(expr.as_function_expression.body, out, depth + 1);
    case APPLY:
      out.append_string("apply:\n");
      _serialize_tree(expr.as_apply_expression.function, out, depth + 1);
      _serialize_tree(expr.as_apply_expression.argument, out, depth + 1);
    case LET:
      String let_txt = string::format(tmem, "let(multiline=%s):\n", expr.as_let_expression.multiline ? "true" : "false");
      out.append_string(let_txt);
      foreach (BindingExpression* binding : expr.as_let_expression.bindings) {
        _serialize_tree((Expression*)binding, out, depth + 1);
      }
      for (int i = 0; i < depth + 1; i++) {
        out.append_string(" ");
      }
      out.append_string("in:\n");
      _serialize_tree(expr.as_let_expression.body, out, depth + 2);
    case WITH:
      out.append_string("with:\n");
      _serialize_tree(expr.as_with_expression.expression, out, depth + 1);
      for (int i = 0; i < depth + 1; i++) {
        out.append_string(" ");
      }
      out.append_string("body:\n");
      _serialize_tree(expr.as_with_expression.body, out, depth + 2);
    case INHERIT:
      out.append_string("inherit(");
      bool first = true;
      foreach (String name : expr.as_inherit_expression.names) {
        if (!first) out.append_string(", ");
        first = false;
        out.append_string(name);
      }
      out.append_string(")\n");
    case FORMALS:
      out.append_string("formals:\n");
      foreach (FormalExpression* formal : expr.as_formals_expression.formals) {
        _serialize_tree((Expression*)formal, out, depth + 1);
      }
    case FORMAL:
      if (expr.as_formal_expression.default_value) {
        String formal_txt = string::format(tmem, "formal(%s, default):\n", expr.as_formal_expression.name);
        out.append_string(formal_txt);
        _serialize_tree(expr.as_formal_expression.default_value, out, depth + 1);
      } else {
        String formal_txt = string::format(tmem, "formal(%s)\n", expr.as_formal_expression.name);
        out.append_string(formal_txt);
      }
    case PAREN:
      out.append_string("paren:\n");
      _serialize_tree(expr.as_paren_expression.expression, out, depth + 1);
  }
}

fn String serialize_tree(Expression* expr) {
  DString out = dstring::new(tmem, "");
  _serialize_tree(expr, &out);
  return out.str_view();
}

// [serialization code]
fn void _serialize_code(Expression* expr, DString* out, int depth = 0) {
  if (!expr) return;

  switch (expr.as_base_expression.type) {
    case ATTRSET:
      // Handle rec prefix
      if (expr.as_attrset_expression.is_rec) {
        out.append_string("rec ");
      }
      // Handle let prefix
      if (expr.as_attrset_expression.is_let) {
        out.append_string("let ");
      }
      // Handle multiline formatting
      if (expr.as_attrset_expression.multiline) {
        out.append_string("{\n");
        foreach (BindingExpression* binding : expr.as_attrset_expression.bindings) {
          // Add indentation for each binding
          for (int i = 0; i < depth + 1; i++) {
            out.append_string("  ");
          }
          _serialize_code((Expression*)binding, out, depth + 1);
          out.append_string("\n");
        }
        // Add indentation for closing brace
        for (int i = 0; i < depth; i++) {
          out.append_string("  ");
        }
        out.append_string("}");
      } else {
        out.append_string("{ ");
        foreach (i, binding : expr.as_attrset_expression.bindings) {
          if (i > 0) out.append_string(" ");
          _serialize_code((Expression*)binding, out, depth);
        }
        out.append_string(" }");
      }
    case BINDING:
      if (expr.as_binding_expression.indentifier == "inherit") {
        // This is an inherit wrapped in binding - just serialize the inherit
        _serialize_code(expr.as_binding_expression.expression, out, depth);
      } else {
        out.append_string(expr.as_binding_expression.indentifier);
        out.append_string(" = ");
        _serialize_code(expr.as_binding_expression.expression, out, depth);
        out.append_string(";");
      }
    case BINARY:
      out.append_string("(");
      _serialize_code(expr.as_binary_expression.left, out, depth);
      out.append_string(" ");
      out.append_string(expr.as_binary_expression.operator);
      out.append_string(" ");
      _serialize_code(expr.as_binary_expression.right, out, depth);
      out.append_string(")");
    case INTEGER:
      out.append_string(expr.as_integer_expression.value);
    case STRING:
      out.append_char('"');
      out.append_string(expr.as_string_expression.value);
      out.append_char('"');
    case VARIABLE:
      out.append_string(expr.as_variable_expression.name);
    case SELECT:
      _serialize_code(expr.as_select_expression.expression, out, depth);
      out.append_char('.');
      out.append_string(expr.as_select_expression.attrpath);
    case LIST:
      if (expr.as_list_expression.multiline) {
        out.append_string("[\n");
        foreach (Expression* elem : expr.as_list_expression.elements) {
          // Add indentation for each element
          for (int i = 0; i < depth + 1; i++) {
            out.append_string("  ");
          }
          _serialize_code(elem, out, depth + 1);
          out.append_string("\n");
        }
        // Add indentation for closing bracket
        for (int i = 0; i < depth; i++) {
          out.append_string("  ");
        }
        out.append_string("]");
      } else {
        out.append_char('[');
        foreach (Expression* elem : expr.as_list_expression.elements) {
          out.append_char(' ');
          _serialize_code(elem, out, depth);
        }
        out.append_string(" ]");
      }
    case FUNCTION:
      _serialize_code((Expression*)expr.as_function_expression.formals, out, depth);
      out.append_string(": ");
      _serialize_code(expr.as_function_expression.body, out, depth);
    case APPLY:
      _serialize_code(expr.as_apply_expression.function, out, depth);
      out.append_char(' ');
      _serialize_code(expr.as_apply_expression.argument, out, depth);
    case LET:
      if (expr.as_let_expression.multiline) {
        out.append_string("let\n");
        foreach (BindingExpression* binding : expr.as_let_expression.bindings) {
          // Add indentation for each binding
          for (int i = 0; i < depth + 1; i++) {
            out.append_string("  ");
          }
          _serialize_code((Expression*)binding, out, depth + 1);
          out.append_string("\n");
        }
        // Add indentation for 'in'
        for (int i = 0; i < depth; i++) {
          out.append_string("  ");
        }
        out.append_string("in ");
        _serialize_code(expr.as_let_expression.body, out, depth);
      } else {
        out.append_string("let ");
        foreach (BindingExpression* binding : expr.as_let_expression.bindings) {
          _serialize_code((Expression*)binding, out, depth);
          out.append_char(' ');
        }
        out.append_string("in ");
        _serialize_code(expr.as_let_expression.body, out, depth);
      }
    case WITH:
      out.append_string("with ");
      _serialize_code(expr.as_with_expression.expression, out, depth);
      out.append_string("; ");
      _serialize_code(expr.as_with_expression.body, out, depth);
    case INHERIT:
      out.append_string("inherit ");
      foreach (String name : expr.as_inherit_expression.names) {
        out.append_string(name);
      }
      out.append_string(";");
    case FORMALS:
      out.append_char('{');
      bool first = true;
      foreach (FormalExpression* formal : expr.as_formals_expression.formals) {
        if (!first) out.append_string(", ");
        first = false;
        _serialize_code((Expression*)formal, out, depth);
      }
      out.append_char('}');
    case FORMAL:
      out.append_string(expr.as_formal_expression.name);
      if (expr.as_formal_expression.default_value) {
        out.append_string("? ");
        _serialize_code(expr.as_formal_expression.default_value, out, depth);
      }
    case PAREN:
      out.append_char('(');
      _serialize_code(expr.as_paren_expression.expression, out, depth);
      out.append_char(')');
  }
}

fn String serialize_code(Expression* expr) {
  DString out = dstring::new(tmem, "");
  _serialize_code(expr, &out);
  return out.str_view();
}

// [remove outputs except dev-shell]

// Helper to find a binding in an attrset by identifier
fn BindingExpression* find_binding(AttrsetExpression* attrset, String identifier) {
  foreach (BindingExpression* binding : attrset.bindings) {
    if (binding.indentifier == identifier) {
      return binding;
    }
  }
  return null;
}

// Helper to get the innermost attrset from a nested expression structure
// Handles: Function -> Apply -> Function -> Let -> Attrset
// Or more generally: traverses through these expression types to find the attrset
fn AttrsetExpression* get_inner_attrset(Expression* expr) {
  switch (expr.as_base_expression.type) {
    case ATTRSET:
      return &expr.as_attrset_expression;
    case FUNCTION:
      return get_inner_attrset(expr.as_function_expression.body);
    case APPLY:
      // For apply, we need to look at the argument (which is the function passed to eachDefaultSystem)
      return get_inner_attrset(expr.as_apply_expression.argument);
    case LET:
      return get_inner_attrset(expr.as_let_expression.body);
    case PAREN:
      return get_inner_attrset(expr.as_paren_expression.expression);
    default:
      return null;
  }
}

// Filter an attrset to keep only the specified binding paths
// Handles: "packages.dev-shell" style bindings (dotted identifiers)
fn void filter_attrset_bindings(AttrsetExpression* attrset) {
  List{BindingExpression*} new_bindings;
  new_bindings.init(tmem);

  foreach (BindingExpression* binding : attrset.bindings) {
    String ident = binding.indentifier;
    
    // Always keep packages.dev-shell
    if (ident == "packages.dev-shell") {
      new_bindings.push(binding);
    }
    // Skip other packages.* bindings (packages.tts, etc.)
    else if (ident.len >= 9 && ident[:9] == "packages.") {
      // skip
    }
    // Skip all devShells.* bindings (devShells.default, etc.)
    else if (ident.len >= 10 && ident[:10] == "devShells.") {
      // skip
    }
    // Keep everything else
    else {
      new_bindings.push(binding);
    }
  }

  attrset.bindings = new_bindings;
}

// Main function to remove all outputs except dev-shell
fn void remove_outputs_except_devshell(Expression* expr) {
  if (!expr) return;

  // The root should be an attrset (the flake)
  if (expr.as_base_expression.type != ATTRSET) return;

  AttrsetExpression* root_attrset = &expr.as_attrset_expression;

  // Find the outputs binding
  BindingExpression* outputs_binding = find_binding(root_attrset, "outputs");
  if (!outputs_binding) return;

  // Navigate through the nested expression structure to find the inner attrset
  // outputs = { ... }: flake-utils.lib.eachDefaultSystem ({system}: let ... in { ... })
  AttrsetExpression* inner_attrset = get_inner_attrset(outputs_binding.expression);
  if (!inner_attrset) return;

  // Filter the inner attrset to keep only packages.dev-shell
  filter_attrset_bindings(inner_attrset);
}

// [remove unused let definitions]

// Collect all variable names referenced in an expression (recursively)
fn void collect_variable_refs(Expression* expr, List{String}* refs) {
  if (!expr) return;

  switch (expr.as_base_expression.type) {
    case VARIABLE:
      refs.push(expr.as_variable_expression.name);
    case SELECT:
      collect_variable_refs(expr.as_select_expression.expression, refs);
    case APPLY:
      collect_variable_refs(expr.as_apply_expression.function, refs);
      collect_variable_refs(expr.as_apply_expression.argument, refs);
    case FUNCTION:
      collect_variable_refs(expr.as_function_expression.body, refs);
    case LET:
      // For nested let, first collect from body, then from bindings that are used
      foreach (BindingExpression* binding : expr.as_let_expression.bindings) {
        collect_variable_refs(binding.expression, refs);
      }
      collect_variable_refs(expr.as_let_expression.body, refs);
    case ATTRSET:
      foreach (BindingExpression* binding : expr.as_attrset_expression.bindings) {
        collect_variable_refs(binding.expression, refs);
      }
    case BINDING:
      collect_variable_refs(expr.as_binding_expression.expression, refs);
    case INHERIT:
      // Inherit expressions contain variable references
      foreach (String name : expr.as_inherit_expression.names) {
        refs.push(name);
      }
    case LIST:
      foreach (Expression* elem : expr.as_list_expression.elements) {
        collect_variable_refs(elem, refs);
      }
    case WITH:
      collect_variable_refs(expr.as_with_expression.expression, refs);
      collect_variable_refs(expr.as_with_expression.body, refs);
    case BINARY:
      collect_variable_refs(expr.as_binary_expression.left, refs);
      collect_variable_refs(expr.as_binary_expression.right, refs);
    case PAREN:
      collect_variable_refs(expr.as_paren_expression.expression, refs);
    default:
      // Other types don't contain variable references
  }
}

// Helper to check if a string is in a list
fn bool string_in_list(List{String}* list, String str) {
  foreach (String item : *list) {
    if (item == str) return true;
  }
  return false;
}

// Main function to remove unused let definitions
fn void remove_unused_let_definitions(Expression* expr) {
  if (!expr) return;

  // Must be a let expression
  if (expr.as_base_expression.type != LET) return;

  LetExpression* let_expr = &expr.as_let_expression;

  // Keep iterating until no more bindings can be removed
  bool changed = true;
  while (changed) {
    changed = false;

    // Collect all variable references from the body and used bindings
    List{String} refs;
    refs.init(tmem);

    // First, collect from the body
    collect_variable_refs(let_expr.body, &refs);

    // Then, check which bindings are referenced
    List{BindingExpression*} new_bindings;
    new_bindings.init(tmem);

    foreach (BindingExpression* binding : let_expr.bindings) {
      String binding_name = binding.indentifier;

      // Check if this binding name appears in refs
      bool is_used = string_in_list(&refs, binding_name);

      if (is_used) {
        // Keep the binding
        new_bindings.push(binding);
        // Collect references from this binding's value too
        collect_variable_refs(binding.expression, &refs);
      } else {
        // This binding is unused - remove it
        changed = true;
      }
    }

    let_expr.bindings = new_bindings;
  }
}

// [remove unused flake inputs]

// Check if string starts with prefix and return the prefix length
fn bool string_starts_with_len(String str, String prefix, int* len) {
  *len = prefix.len;
  if (str.len < prefix.len) return false;
  for (int i = 0; i < prefix.len; i++) {
    if (str[i] != prefix[i]) return false;
  }
  return true;
}

// Find an input in the inputs attrset by name
fn BindingExpression* find_input_binding(AttrsetExpression* inputs, String name) {
  foreach (BindingExpression* binding : inputs.bindings) {
    // Input bindings are like "nixpkgs.url" - we need to check the part before ".url"
    String ident = binding.indentifier;
    // Build expected prefix: "name."
    DString prefix = dstring::new(tmem, "");
    prefix.append_string(name);
    prefix.append_char('.');
    String prefix_str = prefix.str_view();

    if (ident.len >= prefix_str.len && ident[:prefix_str.len] == prefix_str) {
      return binding;
    } else if (ident == name) {
      // Direct input without .url suffix
      return binding;
    }
  }
  return null;
}

// Remove a formal from the formals list by name
fn void remove_formal_by_name(FormalsExpression* formals, String name) {
  List{FormalExpression*} new_formals;
  new_formals.init(tmem);
  foreach (FormalExpression* formal : formals.formals) {
    if (formal.name != name) {
      new_formals.push(formal);
    }
  }
  formals.formals = new_formals;
}

// Main function to remove unused flake inputs
fn void remove_unused_flake_inputs(Expression* expr) {
  if (!expr) return;
  if (expr.as_base_expression.type != ATTRSET) return;

  AttrsetExpression* root_attrset = &expr.as_attrset_expression;

  // Find inputs binding
  BindingExpression* inputs_binding = find_binding(root_attrset, "inputs");
  if (!inputs_binding) return;

  // Find outputs binding
  BindingExpression* outputs_binding = find_binding(root_attrset, "outputs");
  if (!outputs_binding) return;

  // Get the outputs function
  Expression* outputs_expr = outputs_binding.expression;
  if (outputs_expr.as_base_expression.type != FUNCTION) return;
  FunctionExpression* outputs_func = &outputs_expr.as_function_expression;

  // Get the formals (input parameters)
  if (!outputs_func.formals) return;
  FormalsExpression* outputs_formals = outputs_func.formals;

  // Collect all variable references from the outputs function body
  List{String} refs;
  refs.init(tmem);
  collect_variable_refs(outputs_func.body, &refs);

  // Always keep "self" as it's a special input
  refs.push("self");

  // Get inputs attrset
  if (inputs_binding.expression.as_base_expression.type != ATTRSET) return;
  AttrsetExpression* inputs_attrset = &inputs_binding.expression.as_attrset_expression;

  // Build list of used inputs
  List{String} used_inputs;
  used_inputs.init(tmem);

  // Also track new bindings list
  List{BindingExpression*} new_bindings;
  new_bindings.init(tmem);

  foreach (BindingExpression* binding : inputs_attrset.bindings) {
    String ident = binding.indentifier;
    String input_name;
    // Find the dot in the identifier
    for (int i = 0; i < ident.len; i++) {
      if (ident[i] == '.') {
        input_name = ident[:i];
        break;
      }
    }
    if (input_name.len == 0) {
      input_name = ident;
    }

    // Check if this input is used
    bool is_used = string_in_list(&refs, input_name);

    if (is_used) {
      new_bindings.push(binding);
      used_inputs.push(input_name);
    }
  }

  inputs_attrset.bindings = new_bindings;

  // Remove unused formals from outputs
  remove_formal_by_name(outputs_formals, "tts");  // Remove tts if it exists

  // Also remove other unused inputs from formals
  List{FormalExpression*} new_formals;
  new_formals.init(tmem);
  foreach (FormalExpression* formal : outputs_formals.formals) {
    if (string_in_list(&used_inputs, formal.name) || formal.name == "self") {
      new_formals.push(formal);
    }
  }
  outputs_formals.formals = new_formals;

  // Finally, call remove_outputs_except_devshell to clean up packages/devShells
  remove_outputs_except_devshell(expr);
}
