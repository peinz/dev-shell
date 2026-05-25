module ts;

import std::io;

fn void ts_point_to_line_col(TsPoint point, uint* line, uint* col) {
  *line = point.row;
  *col = point.column;
}

fn String node_get_text(TsNode node, String* _source) {
  String source = *_source;
  uint start = node_start_byte(node);
  uint end = node_end_byte(node);
  if (end <= start || start >= source.len) {
    return "";
  }
  if (end > source.len) {
    end = source.len;
  }
  return source[start..end-1];
}

// Recursive function to print the tree
fn void print_tree_cursor(TsTreeCursor *cursor, int depth) {
  TsNode node = tree_cursor_current_node(cursor);

  // We only want to print "Named" nodes (the actual AST). 
  // Anonymous nodes are punctuation like '{', '}', and ';'.
  // if (!node_is_named(node)) {
  //   return;
  // }

  // 1. Print indentation
  for (int i = 0; i < depth; i++) {
    io::printf("  ");
  }

  // 2. Print field name if it exists (e.g., "condition: ")
  ZString field_name = tree_cursor_current_field_name(cursor);
  if (field_name) {
    io::printf("%s: ", field_name);
  }

  // 3. Print the node type
  io::printf("(%s", node_type(node));

  // 4. Traverse children
  if (tree_cursor_goto_first_child(cursor)) {
    io::printf("\n");

    do {
      // Recursively print children
      print_tree_cursor(cursor, depth + 1);
    } while (tree_cursor_goto_next_sibling(cursor));

    // Go back up to the parent
    tree_cursor_goto_parent(cursor);

    // Print closing parenthesis with indentation
    for (int i = 0; i < depth; i++) {
      io::printf("  ");
    }
    io::printf(")\n");
  } else {
    // If there are no children, close the parenthesis on the same line
    io::printf(")\n");
  }
}

// Helper function to initialize the cursor and start printing
fn void print_syntax_tree(TsNode root_node) {
  TsTreeCursor cursor = tree_cursor_new(root_node);
  print_tree_cursor(&cursor, 0);
  tree_cursor_delete(&cursor);
}
