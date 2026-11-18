// An example of parse_command: a program with commands, like git. The options
// before the command are global; each command reads its own.
//
//   goose run examples/subcommand.goose -- -v remote add -f upstream https://x
//   goose run examples/subcommand.goose -- status
//   goose run examples/subcommand.goose -- --help

import std;
import os;
import meiryo from "..";

let GLOBAL_SPEC = """
    -h, --help          show this help
    -v, --verbose       print more
    """;

let ADD_SPEC = """
    -f, --fetch         fetch the remote after adding it
    """;

struct GlobalOptions {
    help:    bool = false,
    verbose: bool = false,
}

struct AddOptions {
    fetch: bool = false,
}

// For a command with no options of its own.
struct NoOptions {
}

// Runs `remote add [-f] <name> <url>`. `sub_argv` starts with "add".
fn remote_add<S>(sub_argv: const S[:], verbose: bool) {
    let add_opts = meiryo::parse_spec(ADD_SPEC);
    var add_options = AddOptions { .. };
    var words: (const u8[:])[>..] = [];

    let result = meiryo::parse_into(add_options, sub_argv, add_opts, words);
    guard meiryo::ok(result) else {
        // The error is an index into sub_argv, the arguments that were parsed.
        var message: u8[>..] = [];
        meiryo::format_error(message, result, sub_argv);
        print("error: ", message);
        return;
    }
    guard words.len == 2 else {
        print("error: usage: remote add [-f] <name> <url>");
        return;
    }
    print("add remote ", words[0], " at ", words[1], " fetch=", add_options.fetch, " verbose=", verbose);
}

// Runs `status`. `sub_argv` starts with "status".
fn status<S>(sub_argv: const S[:], verbose: bool) {
    var no_options = NoOptions { .. };
    let no_opts = meiryo::parse_spec("");
    let result = meiryo::parse_into(no_options, sub_argv, no_opts);
    guard meiryo::ok(result) else {
        var message: u8[>..] = [];
        meiryo::format_error(message, result, sub_argv);
        print("error: ", message);
        return;
    }
    print("status verbose=", verbose);
}

// Runs `remote <command>`. `sub_argv` starts with "remote".
fn remote<S>(sub_argv: const S[:], verbose: bool) {
    var no_options = NoOptions { .. };
    let no_opts = meiryo::parse_spec("");
    let result, command, rest = meiryo::parse_command(no_options, sub_argv, no_opts);
    guard meiryo::ok(result) else {
        var message: u8[>..] = [];
        meiryo::format_error(message, result, sub_argv);
        print("error: ", message);
        return;
    }
    if command == "add" {
        remote_add(rest, verbose);
    } else if command == "" {
        print("error: usage: remote add [-f] <name> <url>");
    } else {
        print("error: unknown command: remote ", command);
    }
}

fn main() {
    let global_opts = meiryo::parse_spec(GLOBAL_SPEC);
    let argv = args();
    var global_options = GlobalOptions { .. };

    let result, command, sub_argv = meiryo::parse_command(global_options, argv, global_opts);
    guard meiryo::ok(result) else {
        var message: u8[>..] = [];
        meiryo::format_error(message, result, argv);
        print("error: ", message);
        return;
    }
    if global_options.help || command == "" {
        var help: u8[>..] = [];
        meiryo::format_help(help, "subcommand", global_opts, "<command> [args...]");
        print(help);
        print("");
        print("""
            commands:
              remote add [-f] <name> <url>    add a remote
              status                          show the state
            """);
        return;
    }
    if command == "remote" {
        remote(sub_argv, global_options.verbose);
    } else if command == "status" {
        status(sub_argv, global_options.verbose);
    } else {
        print("error: unknown command: ", command);
    }
}
