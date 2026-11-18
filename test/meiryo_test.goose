// Tests of meiryo.goose. Each case is a command line split at spaces, and what
// each_arg handed to its block, or the error it stopped with, written out
// as text: "k=value" per option (k being the index in OPTS), "+value" per
// positional argument.
//
//   goose run test/meiryo_test.goose

import std;
import meiryo from "..";

fn options() {
    return [
        meiryo::Opt { long: "help", short: 'h', help: "show this help" },
        meiryo::Opt { long: "silent", short: 's', help: "print nothing" },
        meiryo::Opt { long: "verbose", short: 'v', help: "print more" },
        meiryo::Opt { long: "frames", short: 'f', takes_value: true, value_name: "N", help: "stop after N frames" },
        meiryo::Opt { long: "name", takes_value: true, help: "a name" },
    ];
}

var failures = 0;
var cases = 0;

fn check(line: const u8[:], expected: const u8[:]) {
    cases++;
    let opts = options();
    let text = str("prog ", line);
    let argv = split(text, ' ');
    var got: u8[>..] = [];
    let result = meiryo::each_arg(argv, opts) { opt_index, value =>
        if got.len > 0 {
            got.push(' ');
        }
        if opt_index < 0 {
            format(got, "+", value);
        } else {
            format(got, opt_index, "=", value);
        }
    };
    if !meiryo::ok(result) {
        if got.len > 0 {
            got.push(' ');
        }
        got.append("error: ");
        meiryo::format_error(got, result, argv);
    }
    if got != expected {
        failures++;
        print("FAIL [", line, "]\n  expected: ", expected, "\n  got:      ", got);
    }
}

// parse_spec and parse_into: the same command line read into a struct.
let SPEC = """
    -h, --help            show this help
    -v, --verbose         print more
    -f, --frames <N>      stop after N frames
        --scale <FACTOR>  zoom factor
        --name <NAME>     a name
        --dry-run         change nothing
    """;

struct Options {
    help:    bool        = false,
    verbose: bool        = false,
    frames:  i64         = -1,
    scale:   f64         = 1.0,
    name:    const u8[:] = "",
    dry_run: bool        = false,
}

// The struct and the positional arguments as text, or the error.
fn check_into(line: const u8[:], expected: const u8[:]) {
    cases++;
    let opts = meiryo::parse_spec(SPEC);
    let text = str("prog ", line);
    let argv = split(text, ' ');
    var options = Options { .. };
    var files: (const u8[:])[>..] = [];
    let result = meiryo::parse_into(options, argv, opts, files);
    var got: u8[>..] = [];
    if meiryo::ok(result) {
        format(got, options, " ", files);
    } else {
        got.append("error: ");
        meiryo::format_error(got, result, argv);
    }
    if got != expected {
        failures++;
        print("FAIL into [", line, "]\n  expected: ", expected, "\n  got:      ", got);
    }
}

// The same, with the parse_into that takes no positional arguments.
fn check_into_no_positional(line: const u8[:], expected: const u8[:]) {
    cases++;
    let opts = meiryo::parse_spec(SPEC);
    let text = str("prog ", line);
    let argv = split(text, ' ');
    var options = Options { .. };
    let result = meiryo::parse_into(options, argv, opts);
    var got: u8[>..] = [];
    if meiryo::ok(result) {
        format(got, options);
    } else {
        got.append("error: ");
        meiryo::format_error(got, result, argv);
    }
    if got != expected {
        failures++;
        print("FAIL into, no positional [", line, "]\n  expected: ", expected, "\n  got:      ", got);
    }
}

// parse_command: the struct, the command and what follows it, or the error.
fn check_command(line: const u8[:], expected: const u8[:]) {
    cases++;
    let opts = meiryo::parse_spec(SPEC);
    let text = str("prog ", line);
    let argv = split(text, ' ');
    var options = Options { .. };
    let result, command, sub_argv = meiryo::parse_command(options, argv, opts);
    var got: u8[>..] = [];
    if meiryo::ok(result) {
        format(got, options, " ", command, " ", sub_argv);
    } else {
        got.append("error: ");
        meiryo::format_error(got, result, argv);
        format(got, " | ", command, " ", sub_argv);
    }
    if got != expected {
        failures++;
        print("FAIL command [", line, "]\n  expected: ", expected, "\n  got:      ", got);
    }
}

fn main() {
    // Long options.
    check("--silent", "1=");
    check("--frames 10", "3=10");
    check("--frames=10", "3=10");
    check("--frames=", "3=");
    check("--name=a=b", "4=a=b");

    // Short options, alone and together.
    check("-s", "1=");
    check("-sv", "1= 2=");
    check("-f 3", "3=3");
    check("-f3", "3=3");
    check("-vf3", "2= 3=3");
    check("-vf 3", "2= 3=3");
    check("-f=3", "3=3");
    check("-vf=3", "2= 3=3");
    check("-f=", "3=");

    // Only the first "=" separates: a value starting with "=" keeps the rest.
    check("-f==3", "3==3");
    check("--frames==3", "3==3");

    // Positional arguments.
    check("a b", "+a +b");
    check("-", "+-");
    check("-- --silent -x", "+--silent +-x");
    check("a --silent b", "+a 1= +b");

    // A value that looks like an option is still the value.
    check("--frames --silent", "3=--silent");

    // Errors: what came before is handed over, the bad argument is not.
    check("--bogus", "error: unknown option: --bogus");
    check("-s -x", "1= error: unknown option: -x");
    check("-sx", "1= error: unknown option: -sx");
    check("--frames", "error: missing value for --frames");
    check("-vf", "2= error: missing value for -vf");
    check("--silent=1", "error: option takes no value: --silent=1");

    // Help: the lines separated by line breaks, the last without one.
    var help: u8[>..] = [];
    meiryo::format_help(help, "prog", options(), "<file>...");
    cases++;
    let expected_help = str(
        "usage: prog [options] <file>...\n",
        "  -h, --help                show this help\n",
        "  -s, --silent              print nothing\n",
        "  -v, --verbose             print more\n",
        "  -f, --frames <N>          stop after N frames\n",
        "      --name <VALUE>        a name");
    if help != expected_help {
        failures++;
        print("FAIL help\n", help);
    }

    // parse_into: each field type, and the defaults of options not given.
    check_into("-v", "Options { false, true, -1, 1.0, \"\", false } []");
    check_into("-v -f 12 --scale=2.5 --name joe --dry-run a b", "Options { false, true, 12, 2.5, \"joe\", true } [\"a\", \"b\"]");
    check_into("-f 3 -f 4", "Options { false, false, 4, 1.0, \"\", false } []");
    check_into("-- -v", "Options { false, false, -1, 1.0, \"\", false } [\"-v\"]");

    // parse_into errors: a value that does not parse is reported at its option.
    check_into("-f abc", "error: invalid value for -f");
    check_into("--frames=abc", "error: invalid value for --frames=abc");
    check_into("--scale x", "error: invalid value for --scale");
    check_into("--name", "error: missing value for --name");
    check_into("--bogus", "error: unknown option: --bogus");
    check_into_no_positional("-v", "Options { false, true, -1, 1.0, \"\", false }");
    check_into_no_positional("-v stray", "error: unexpected argument: stray");

    // parse_command: the first positional argument is the command, and what
    // follows it, the command included, is left for the command to parse.
    check_command("-v remote add -f x", "Options { false, true, -1, 1.0, \"\", false } remote [\"remote\", \"add\", \"-f\", \"x\"]");
    check_command("remote", "Options { false, false, -1, 1.0, \"\", false } remote [\"remote\"]");
    check_command("-v", "Options { false, true, -1, 1.0, \"\", false }  []");
    check_command("--name remote", "Options { false, false, -1, 1.0, \"remote\", false }  []");
    check_command("-- -x", "Options { false, false, -1, 1.0, \"\", false } -x [\"-x\"]");
    check_command("-", "Options { false, false, -1, 1.0, \"\", false } - [\"-\"]");
    check_command("remote --bogus", "Options { false, false, -1, 1.0, \"\", false } remote [\"remote\", \"--bogus\"]");
    check_command("--bogus remote", "error: unknown option: --bogus |  []");
    check_command("-f abc remote", "error: invalid value for -f |  []");
    check_command("-- -x --verbose", "Options { false, false, -1, 1.0, \"\", false } -x [\"-x\", \"--verbose\"]");

    // A command parsed again on sub_argv: nested commands.
    cases++;
    let nested_opts = meiryo::parse_spec(SPEC);
    let nested_argv = split("prog -v remote -v add x", ' ');
    var outer = Options { .. };
    let outer_result, outer_command, outer_argv = meiryo::parse_command(outer, nested_argv, nested_opts);
    var inner = Options { .. };
    let inner_result, inner_command, inner_argv = meiryo::parse_command(inner, outer_argv, nested_opts);
    var nested_got: u8[>..] = [];
    format(nested_got, meiryo::ok(outer_result), " ", outer.verbose, " ", outer_command, " ", outer_argv, " ");
    format(nested_got, meiryo::ok(inner_result), " ", inner.verbose, " ", inner_command, " ", inner_argv);
    if nested_got != "true true remote [\"remote\", \"-v\", \"add\", \"x\"] true true add [\"add\", \"x\"]" {
        failures++;
        print("FAIL nested command\n  got: ", nested_got);
    }

    // An error in the arguments of a command is reported with sub_argv, the
    // array its position counts in.
    cases++;
    let error_argv = split("prog remote --bogus", ' ');
    var error_options = Options { .. };
    let _, error_command, error_sub_argv = meiryo::parse_command(error_options, error_argv, nested_opts);
    let error_result = meiryo::parse_into(error_options, error_sub_argv, nested_opts);
    var error_got: u8[>..] = [];
    meiryo::format_error(error_got, error_result, error_sub_argv);
    if error_command != "remote" || error_got != "unknown option: --bogus" {
        failures++;
        print("FAIL sub_argv error\n  command: ", error_command, "\n  got: ", error_got);
    }

    // parse_spec: what it read, as the help prints it.
    var spec_help: u8[>..] = [];
    meiryo::format_help(spec_help, "prog", meiryo::parse_spec(SPEC));
    cases++;
    let expected_spec_help = str(
        "usage: prog [options]\n",
        "  -h, --help                show this help\n",
        "  -v, --verbose             print more\n",
        "  -f, --frames <N>          stop after N frames\n",
        "      --scale <FACTOR>      zoom factor\n",
        "      --name <NAME>         a name\n",
        "      --dry-run             change nothing");
    if spec_help != expected_spec_help {
        failures++;
        print("FAIL spec help\n", spec_help);
    }

    if failures > 0 {
        print(failures, " of ", cases, " cases failed");
        exit(1);
    }
    print("all ", cases, " cases passed");
}
