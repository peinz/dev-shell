module main;

import std::io;
import std::io::path;
import std::io::file;
import std::os;
import std::collections::list;
import libc;
import nix_parser;
import ts;

extern fn CInt execvp(ZString file, ZString* argv);
extern fn CInt system(ZString command);
extern fn void* malloc(usz size);
extern fn CInt stat(ZString path, libc::Stat* buf);

struct DevShellConfig {
    String flake_content;
}

fn usz get_file_mtime(Path path) {
    libc::Stat st;
    if (stat((ZString)path.str_view(), &st) == 0) {
        return (usz)st.st_mtime;
    }
    return 0;
}

fn bool is_project_folder(Path path) {
  Path flake_path = path.tappend("/flake.nix")!!;
  if (path::exists(flake_path)) return true;

  Path git_path = path.tappend("/.git")!!;
  if (path::exists(git_path)) return true;

  Path project_json_path = path.tappend("/project.json")!!;
  if (path::exists(project_json_path)) return true;

  Path package_json_path = path.tappend("/package.json")!!;
  if (path::exists(package_json_path)) return true;

  Path pupspec_yaml_path = path.tappend("/pupspec.yaml")!!;
  if (path::exists(pupspec_yaml_path)) return true;

  return false;
}

fn String get_path_project_string(Path path) {
  List{String} projects;
  while (true) {
    Path? parent = path.parent();
    if (catch parent) break;

    if (is_project_folder(path)) {
      projects.push_front(path.basename());
    }

    path = parent;
  }

  String result = "";
  foreach (project : projects) {
    if (result != "") result = result.tconcat("/");
    result = result.tconcat(project);
  }

  return result;
}

fn void find_flake_nix(Path* out_path, bool* found) {
    Path search_dir = path::tcwd()!!;
    String prev_path = "";
    *found = false;

    while (search_dir.path_string.len > 0 && search_dir.path_string != prev_path) {
        Path flake_path = search_dir.tappend("/flake.nix")!!;
        if (path::exists(flake_path)) {
            *out_path = search_dir;
            *found = true;
            return;
        }
        
        if (try Path parent = search_dir.parent()) {
            prev_path = search_dir.path_string;
            search_dir = parent;
        } else {
            return;
        }
    }
}

fn void extract_devshell_config(Path project_root, DevShellConfig* out_config, bool* found) {
    *found = false;
    Path flake_path = project_root.tappend("/flake.nix")!!;

    if (!path::exists(flake_path)) {
        return;
    }

    File f = file::open(flake_path.str_view(), "r")!!;
    defer (void)f.close()!!;

    usz file_size = 0;
    if (try size = file::get_size(flake_path.str_view())) {
        file_size = size;
    }

    if (file_size == 0) {
        return;
    }

    void* buffer_ptr = malloc(file_size + 1);
    char[] buffer = (char[])buffer_ptr[:file_size + 1];
    usz bytes_read = f.read(buffer[:file_size])!!;
    buffer[bytes_read] = '\0';

    String content = (String)buffer[:bytes_read + 1];

    TsTree* tree = nix_parser::parse_ts_nix_tree(content);
    if (tree == null) {
        io::printn("Error: Failed to parse flake.nix with tree-sitter");
        return;
    }
    defer ts::tree_delete(tree);

    TsNode root = ts::tree_root_node(tree);
    Expression*? ast_opt = nix_parser::tr_source(root, &content);
    if (catch ast_opt) {
        io::printn("Error: Failed to translate tree-sitter AST");
        return;
    }
    Expression* ast = ast_opt;

    // Rewrite the AST in-place: keep only inputs referenced by outputs,
    // prune outputs to just packages.dev-shell, and drop unused let-bindings.
    nix_parser::remove_unused_flake_inputs(ast);
    Expression* let_expr = nix_parser::find_let_in_outputs(ast);
    if (let_expr != null) {
        nix_parser::remove_unused_let_definitions(let_expr);
    }

    out_config.flake_content = nix_parser::serialize_code(ast);

    *found = true;
}

fn void generate_devshell_flake(Path project_root, DevShellConfig config) {
    Path dev_shell_dir = project_root.tappend("/.dev-shell")!!;
    path::mkdir(dev_shell_dir, true)!!;

    Path flake_path = dev_shell_dir.tappend("/flake.nix")!!;

    io::printn("Generating .dev-shell/flake.nix...");

    File f = file::open(flake_path.str_view(), "w")!!;
    (void)f.write(config.flake_content)!!;
    (void)f.write("\n")!!;
    (void)f.flush()!!;
    (void)f.close()!!;

    Path gitignore_path = dev_shell_dir.tappend("/.gitignore")!!;
    File gf = file::open(gitignore_path.str_view(), "w")!!;
    (void)gf.write("*\n")!!;
    (void)gf.flush()!!;
    (void)gf.close()!!;
}

fn void main() {
    Path project_root;
    bool found_flake = false;
    find_flake_nix(&project_root, &found_flake);

    if (found_flake) {
        DevShellConfig config = { "" };
        bool config_found = false;
        extract_devshell_config(project_root, &config, &config_found);

        if (config_found) {
            Path ds_dir = project_root.tappend("/.dev-shell")!!;

            Path generated_flake = ds_dir.tappend("/flake.nix")!!;
            bool needs_regeneration = false;

            if (path::exists(generated_flake)) {
                Path original_flake_path = project_root.tappend("/flake.nix")!!;
                usz original_mtime = get_file_mtime(original_flake_path);
                usz generated_mtime = get_file_mtime(generated_flake);

                if (original_mtime > generated_mtime) {
                    io::printn("Original flake.nix is newer than generated, regenerating...");
                    needs_regeneration = true;
                }
            } else {
                needs_regeneration = true;
            }

            if (needs_regeneration) {
                generate_devshell_flake(project_root, config);
                // Delete stale lock so nix regenerates it against the new inputs
                Path lock_path = ds_dir.tappend("/flake.lock")!!;
                if (path::exists(lock_path)) {
                    (void)file::delete(lock_path.str_view());
                }
                (void)path::chdir(ds_dir)!!;
                system("nix build path:.#dev-shell");
            } else {
                Path result_path = ds_dir.tappend("/result/bin/dev-shell")!!;
                if (!path::exists(result_path)) {
                    (void)path::chdir(ds_dir)!!;
                    system("nix build path:.#dev-shell");
                }
            }

            String dir_name = project_root.basename();
            if (dir_name.len == 0) {
                dir_name = "/";
            }

            Path exec_path = ds_dir.tappend("/result/bin/dev-shell")!!;

            ZString exec_path_z = (ZString)exec_path.str_view();
            ZString dir_name_z = (ZString)dir_name;

            String project_path = get_path_project_string(project_root);
            ZString[] args = {
              exec_path_z,
              project_path.zstr_copy(tmem),
              project_root.str_view().zstr_copy(tmem),
              null,
            };

            execvp(exec_path_z, args);

            io::printn("Error: Failed to execute dev-shell");
            os::exit(1);
        } else {
            io::printn("Error: Could not extract pkgs/deps from flake.nix");
            os::exit(1);
        }
    } else {
        io::printn("Error: Could not find flake.nix in parent directories");
        os::exit(1);
    }
}
