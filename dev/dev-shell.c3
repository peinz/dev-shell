module main;

import std::io;
import std::io::path;
import std::io::file;
import std::os;
import std::time::datetime;
import libc;

extern fn CInt access(ZString path, CInt mode);
extern fn CInt execvp(ZString file, ZString* argv);
extern fn CInt system(ZString command);
extern fn void* malloc(usz size);
extern fn CInt stat(ZString path, libc::Stat* buf);

const int X_OK = 1;

struct GeneratedMetadata {
    String timestamp;
    String pkgs_def;
    String deps;
}

struct DevShellConfig {
    String pkgs_def;
    String deps;
}

fn usz get_file_mtime(Path path) {
    libc::Stat st;
    if (stat((ZString)path.str_view(), &st) == 0) {
        return (usz)st.st_mtime;
    }
    return 0;
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

fn bool parse_generated_flake_metadata(Path flake_path, GeneratedMetadata* out_meta) {
    if (!path::exists(flake_path)) {
        return false;
    }
    
    File f = file::open(flake_path.str_view(), "r")!!;
    defer (void)f.close()!!;
    
    char[512] first_lines;
    usz bytes_read = f.read(first_lines[..510])!!;
    if (bytes_read == 0) {
        return false;
    }
    
    first_lines[bytes_read] = '\0';
    String content = (String)first_lines[..bytes_read];
    
    String timestamp = "";
    String pkgs_def = "";
    String deps = "";
    
    usz line_start = 0;
    usz line_end = 0;
    bool found_timestamp = false;
    bool found_pkgs = false;
    bool found_deps = false;
    
    while (line_start < content.len) {
        line_end = line_start;
        while (line_end < content.len && content[line_end] != '\n') {
            line_end++;
        }
        
        if (line_start < line_end) {
            String line = content[line_start..line_end];
            
            if (try idx = line.index_of("# Generated: ")) {
                timestamp = line[13..];
                found_timestamp = true;
            } else if (try idx = line.index_of("# pkgs_def: ")) {
                pkgs_def = line[12..];
                found_pkgs = true;
            } else if (try idx = line.index_of("# deps: ")) {
                deps = line[8..];
                found_deps = true;
            } else if (line.len > 0 && line[0] == '{') {
                break;
            }
        }
        
        line_start = line_end + 1;
        if (line_start >= content.len) break;
    }
    
    io::printfn("parse_generated_flake_metadata: found_timestamp=%b, found_pkgs=%b, found_deps=%b", found_timestamp, found_pkgs, found_deps);
    
    if (!found_timestamp || !found_pkgs || !found_deps) {
        return false;
    }
    
    out_meta.timestamp = timestamp;
    out_meta.pkgs_def = pkgs_def;
    out_meta.deps = deps;
    return true;
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
    
    String pkgs_def = extract_pkgs_def(content);
    if (pkgs_def.len == 0) {
        return;
    }
    
    String deps = extract_deps(content);
    if (deps.len == 0) {
        return;
    }
    
    out_config.pkgs_def = pkgs_def;
    out_config.deps = deps;
    *found = true;
}

fn String extract_pkgs_def(String content) {
    String search = "pkgs = ";
    
    usz start_idx = 0;
    if (try idx = content.index_of(search)) {
        start_idx = idx + search.len;
    } else {
        return "";
    }
    
    usz end_idx = start_idx;
    int brace_count = 0;
    while (end_idx < content.len) {
        char c = content[end_idx];
        if (c == '{') {
            brace_count++;
        } else if (c == '}') {
            brace_count--;
        } else if (c == ';' && brace_count == 0) {
            break;
        }
        end_idx++;
    }
    
    if (end_idx <= start_idx) return "";
    
    String result = content[start_idx..end_idx - 1];
    
    while (result.len > 0 && (result[0] == ' ' || result[0] == '\n' || result[0] == '\t')) {
        result = result[1..];
    }
    while (result.len > 0 && (result[^1] == ' ' || result[^1] == '\n' || result[^1] == '\t')) {
        result = result[..^1];
    }
    if (result.len > 0 && result[^1] == 59) {
        result = result[0:result.len - 1];
        while (result.len > 0 && (result[^1] == ' ' || result[^1] == '\n' || result[^1] == '\t')) {
            result = result[0:result.len - 1];
        }
    }
    
    return result;
}

fn String extract_deps(String content) {
    String search = "deps = with pkgs; [";
    usz start_idx = 0;
    if (try idx = content.index_of(search)) {
        start_idx = idx + search.len;
    } else {
        return "";
    }
    
    usz end_idx = start_idx;
    int bracket_count = 1;
    while (end_idx < content.len && bracket_count > 0) {
        if (content[end_idx] == '[') {
            bracket_count++;
        } else if (content[end_idx] == ']') {
            bracket_count--;
        }
        end_idx++;
    }
    
    if (end_idx <= start_idx) return "";
    
    String result = content[start_idx..end_idx - 2];
    
    while (result.len > 0 && (result[0] == ' ' || result[0] == '\n' || result[0] == '\t')) {
        result = result[1..];
    }
    
    usz end_trim = 0;
    for (usz i = result.len; i > 0; i--) {
        char c = result[i - 1];
        if (c == ' ' || c == '\n' || c == '\t') {
            end_trim++;
        } else {
            break;
        }
    }
    if (end_trim > 0) {
        result = result[0:result.len - end_trim];
    }
    
    return result;
}

fn void int_to_dstring(DString* ds, int val, bool zero_pad) {
    if (val == 0) {
        if (zero_pad) ds.append("0");
        return;
    }
    
    if (zero_pad && val < 10) {
        ds.append("0");
    }
    
    char[16] buf;
    usz len = 0;
    int n = val;
    
    if (n < 0) {
        ds.append("-");
        n = -n;
    }
    
    while (n > 0) {
        buf[len] = (char)('0' + (n % 10));
        len++;
        n = n / 10;
    }
    
    for (usz i = len; i > 0; i--) {
        ds.append(buf[i - 1]);
    }
}

fn void get_current_timestamp(DString* out_timestamp) {
    DateTime dt = datetime::now();
    
    int year_val = (int)dt.year;
    int month_val = (int)dt.month + 1;
    int day_val = (int)(char)dt.day;
    int hour_val = (int)(char)dt.hour;
    int min_val = (int)(char)dt.min;
    int sec_val = (int)(char)dt.sec;
    
    int_to_dstring(out_timestamp, year_val, false);
    out_timestamp.append("-");
    int_to_dstring(out_timestamp, month_val, true);
    out_timestamp.append("-");
    int_to_dstring(out_timestamp, day_val, true);
    out_timestamp.append("T");
    int_to_dstring(out_timestamp, hour_val, true);
    out_timestamp.append(":");
    int_to_dstring(out_timestamp, min_val, true);
    out_timestamp.append(":");
    int_to_dstring(out_timestamp, sec_val, true);
}

fn String flatten_for_comment(String s) {
    DString result = dstring::temp();
    for (usz i = 0; i < s.len; i++) {
        char c = s[i];
        if (c == '\n' || c == '\t') {
            result.append(' ');
        } else {
            result.append(c);
        }
    }
    return result.str_view();
}

fn void generate_devshell_flake(Path project_root, DevShellConfig config) {
    Path dev_shell_dir = project_root.tappend("/.dev-shell")!!;
    path::mkdir(dev_shell_dir, true)!!;
    
    Path flake_path = dev_shell_dir.tappend("/flake.nix")!!;
    
    io::printn("Generating .dev-shell/flake.nix...");
    io::printfn("  Extracted pkgs: %s", config.pkgs_def);
    io::printfn("  Extracted deps: %s", config.deps);
    
    DString timestamp = dstring::temp();
    get_current_timestamp(&timestamp);
    io::printfn("generate_devshell_flake: timestamp='%s'", timestamp.str_view());
    
    DString flake_content = dstring::temp();
    flake_content.append("# Generated: ");
    flake_content.append(timestamp.str_view());
    flake_content.append("\n");
    flake_content.append("# pkgs_def: ");
    String flat_pkgs = flatten_for_comment(config.pkgs_def);
    flake_content.append(flat_pkgs);
    flake_content.append("\n");
    flake_content.append("# deps: ");
    String flat_deps = flatten_for_comment(config.deps);
    flake_content.append(flat_deps);
    flake_content.append("\n");
    flake_content.append("{\n");
    flake_content.append("  inputs = {\n");
    flake_content.append("    nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";\n");
    flake_content.append("    flake-utils.url = \"github:numtide/flake-utils\";\n");
    flake_content.append("    dev-shell.url = \"github:peinz/dev-shell\";\n");
    flake_content.append("  };\n");
    flake_content.append("\n  outputs = { self, nixpkgs, flake-utils, dev-shell }:\n");
    flake_content.append("    flake-utils.lib.eachDefaultSystem (system:\n");
    flake_content.append("      let\n");
    flake_content.append("        pkgs = ");
    flake_content.append(config.pkgs_def);
    flake_content.append(";\n");
    flake_content.append("        deps = with pkgs; [\n");
    flake_content.append(config.deps);
    flake_content.append("\n        ];\n");
    flake_content.append("      in\n");
    flake_content.append("      {\n");
    flake_content.append("        packages.dev-shell = dev-shell.mkShell { inherit pkgs; inherit deps; };\n");
    flake_content.append("        devShells.default = dev-shell.mkShell { inherit pkgs; inherit deps; };\n");
    flake_content.append("      }\n");
    flake_content.append("    );\n");
    flake_content.append("}");
    
    File f = file::open(flake_path.str_view(), "w")!!;
    (void)f.write(flake_content.str_view())!!;
    (void)f.flush()!!;
    (void)f.close()!!;
    
    Path gitignore_path = dev_shell_dir.tappend("/.gitignore")!!;
    File gf = file::open(gitignore_path.str_view(), "w")!!;
    (void)gf.write("result\n")!!;
    (void)gf.flush()!!;
    (void)gf.close()!!;
}

fn void main() {
    Path project_root;
    bool found_flake = false;
    find_flake_nix(&project_root, &found_flake);
    
    if (found_flake) {
        DevShellConfig config = { "", "" };
        bool config_found = false;
        extract_devshell_config(project_root, &config, &config_found);
        
        if (config_found) {
            Path ds_dir = project_root.tappend("/.dev-shell")!!;
            
            Path generated_flake = ds_dir.tappend("/flake.nix")!!;
            bool needs_regeneration = false;
            bool needs_rebuild = false;
            
            if (path::exists(generated_flake)) {
                Path original_flake_path = project_root.tappend("/flake.nix")!!;
                usz original_mtime = get_file_mtime(original_flake_path);
                usz generated_mtime = get_file_mtime(generated_flake);
                
                if (original_mtime > generated_mtime) {
                    io::printn("Original flake.nix is newer than generated, checking for changes...");
                    
                    GeneratedMetadata saved_meta = { "", "", "" };
                    if (parse_generated_flake_metadata(generated_flake, &saved_meta)) {
                        if (config.pkgs_def != saved_meta.pkgs_def || config.deps != saved_meta.deps) {
                            io::printn("Configuration changed, regenerating...");
                            needs_regeneration = true;
                            needs_rebuild = true;
                        } else {
                            io::printn("Configuration unchanged, no regeneration needed.");
                        }
                    } else {
                        io::printn("Could not parse saved metadata, regenerating...");
                        needs_regeneration = true;
                        needs_rebuild = true;
                    }
                }
            } else {
                needs_regeneration = true;
                needs_rebuild = true;
            }
            
            if (needs_regeneration) {
                generate_devshell_flake(project_root, config);
                
                String git_add_cmd = "git -C ";
                DString add_cmd = dstring::temp();
                add_cmd.append(git_add_cmd);
                add_cmd.append(project_root.str_view());
                add_cmd.append(" add .dev-shell");
                system((ZString)add_cmd.str_view());
                
                (void)path::chdir(ds_dir)!!;
                
                String git_add_project_cmd = "git -C ";
                DString add_project_cmd = dstring::temp();
                add_project_cmd.append(git_add_project_cmd);
                add_project_cmd.append(project_root.str_view());
                add_project_cmd.append(" add .");
                system((ZString)add_project_cmd.str_view());
                
                if (needs_rebuild) {
                    system("nix build .#dev-shell");
                }
            } else {
                Path result_path = ds_dir.tappend("/result/bin/dev-shell")!!;
                if (!path::exists(result_path)) {
                    (void)path::chdir(ds_dir)!!;
                    system("nix build .#dev-shell");
                }
            }
            
            String dir_name = project_root.basename();
            if (dir_name.len == 0) {
                dir_name = "/";
            }
            
            Path exec_path = ds_dir.tappend("/result/bin/dev-shell")!!;
            
            ZString exec_path_z = (ZString)exec_path.str_view();
            ZString dir_name_z = (ZString)dir_name;
            
            ZString[] args = { exec_path_z, dir_name_z, null };
            
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