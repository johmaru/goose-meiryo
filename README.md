# meiryo

*meiryo* (明瞭) is Japanese for "clear, easy to understand".

A small command line parser for [Goose](https://github.com/aardappel/goose).
The options are written as a spec, in the form `--help` prints them, and
read into a struct with one field per option. Values are slices into
`argv`, so nothing is copied.

## Using it

Declare the package in your program's root file:

```goose
import meiryo from "github.com/johmaru/goose-meiryo@<tag>";  // once it is published
import meiryo from "../path/to/this/directory";               // or a local checkout
```

Then:

```goose
import std;
import os;
import meiryo from "github.com/johmaru/goose-meiryo@<tag>";

let SPEC = """
    -h, --help          show this help
    -v, --verbose       print more
    -f, --frames <N>    stop after N frames
        --dry-run       change nothing
    """;

struct Options {
    help: bool = false,
    verbose: bool = false,
    frames: i64 = -1,
    dry_run: bool = false,
}

fn main() {
    let opts = meiryo::parse_spec(SPEC);
    let argv = args();
    var options = Options { .. };
    var files: (const u8[:])[>..] = [];

    let result = meiryo::parse_into(options, argv, opts, files);
    guard meiryo::ok(result) else {
        var message: u8[>..] = [];
        meiryo::format_error(message, result, argv);
        print("error: ", message);
        return;
    }
    if options.help {
        var help: u8[>..] = [];
        meiryo::format_help(help, "myprogram", opts, "<file>...");
        print(help);
        return;
    }
    // options.verbose, options.frames, files ...
}
```

`examples/example.goose` is a complete program.

## The spec

One option per line:

```
[-x, ]--long[ <VALUE>][ help text]
```

* `--long` is required; `-x, ` gives it a short name too.
* `<VALUE>` makes the option take a value, shown under that name in the
  help.
* Leading spaces and blank lines are ignored, so a `"""` raw string can be
  indented with the code.
* The `Opt`s that `parse_spec` returns are slices of the spec, so the spec
  must outlive them. A string literal always does.

## The struct

Each field is named after its option, with `-` in the option written `_`
in the field (`--dry-run` fills `dry_run`). A field keeps its value when its
option is not given, so give every field a default.

| Field type | Option | Value stored |
|---|---|---|
| `bool` | a flag (no `<VALUE>`) | `true` when given |
| `i64` | takes a value | `parse_int` of the text, or `BadValue` |
| `f64` | takes a value | `parse_flt` of the text, or `BadValue` |
| `const u8[:]` | takes a value | the text, a slice of `argv` |
| `u8[>..]` | takes a value | a copy of the text |

A field of another type is a compile error. Given more than once, an
option keeps its last value. A `const u8[:]` field holds a slice of `argv`,
so declare the struct after `argv`.

Positional arguments are pushed onto the last argument of `parse_into`.
Leave it out for a program that takes none: a positional argument is then
an `UnexpectedArgument` error.

## Mistakes in the program

These abort with a message naming the option, field or spec line, since
they are bugs in the program rather than in its arguments:

* a spec line not in the form above;
* an empty long name, a long name holding `=`, or a short name that is not
  a visible ASCII character, or is `-` or `=`;
* a field with no option in the spec, or an option with no field;
* a `<VALUE>` on the spec line of a `bool` field, or none on another.

## Accepted forms

| Form | Meaning |
|---|---|
| `--name` | a flag |
| `--name=value` | an option with its value in the same argument |
| `--name value` | an option with its value in the next argument |
| `-n` | a flag by its short name |
| `-abc` | several short flags at once |
| `-nvalue`, `-n value` | a short option with its value |
| `-n=value` | the same; one `=` right after the name is dropped |
| `--` | everything after it is positional |
| `-`, or anything not starting with `-` | a positional argument |

An option that takes a value always takes the next argument, even one
starting with `-`: `--frames --silent` gives `--frames` the value
`--silent`.

Only the first `=` separates the name from the value, so a value that
starts with `=` is written `--frames==3` or `-f==3` (both give `=3`), as
with clap.

## The lower level: each_arg

When a struct does not fit, for example for an option that may be given
many times, `each_arg` calls a block for each argument instead:

```goose
let result = meiryo::each_arg(argv, opts) { opt_index, value =>
    if opt_index < 0 {
        files.push(value);        // a positional argument
    } else if opts[opt_index].long == "include" {
        includes.push(value);
    }
};
```

`opts` can come from `parse_spec` or be written as a table of `meiryo::Opt`.
`each_arg_checked` is the same with a block that returns a `bool`: `false`
rejects the value (`BadValue`) or the positional argument
(`UnexpectedArgument`). `examples/each_arg.goose` is a complete program.

## Subcommands

For a program with commands, like `git remote add`, `parse_command` reads
the options before the command into a struct and splits argv at the command:

```goose
let result, command, sub_argv = meiryo::parse_command(global_options, argv, global_opts);
guard meiryo::ok(result) else {
    var message: u8[>..] = [];
    meiryo::format_error(message, result, argv);
    print("error: ", message);
    return;
}
if command == "status" {
    // ...
} else if command == "" {
    print("error: no command given; see --help");
} else {
    print("error: unknown command: ", command);
}
```

* The command is the first positional argument. An option's value is never
  the command. A `--` before the command only ends the global options, so
  the command may then start with `-`; a `--` meant for the command goes
  after the command: `prog run -- --weird-file`.
* `sub_argv` is argv from the command on, so `sub_argv[0]` is the command's
  name and `sub_argv` can go to `parse_command` or `parse_into` again, which
  is how a command with commands of its own is read.
* With no command, or on an error, the command is `""` and `sub_argv` is
  empty. A command that is not known is for the program to report.
* The `at` of an error from parsing `sub_argv` counts in `sub_argv`, so pass
  `sub_argv` to `format_error(message, result, sub_argv)`, not `argv`.
* Options after the command are the command's own: `parse_command` stops at
  the command and leaves them in `sub_argv`.

`examples/subcommand.goose` is a complete program, with a command under a
command, and a `--help` that lists the commands.

## API

```goose
struct Opt {
    const long: u8[:],                  // the name after "--"
    short: u8 = 0,                      // the letter after "-"; 0 for none
    takes_value: bool = false,
    const value_name: u8[:] = "VALUE",  // shown in the help: --frames <N>
    const help: u8[:] = "",
}

enum Error { None, UnknownOption, MissingValue, UnexpectedValue, BadValue, UnexpectedArgument }
struct Result { error: Error, at: i64 }  // `at` is the index in the argv that was parsed (for a command, its sub_argv), -1 if none

fn parse_spec(spec: const u8[:]) -> Opt[>..]
fn parse_into<T, S>(target: T&, argv: const S[:], opts: const Opt[:], positional: (const u8[:])[>..]&) -> Result
fn parse_into<T, S>(target: T&, argv: const S[:], opts: const Opt[:]) -> Result
fn parse_command<T, S>(target: T&, argv: const S[:], opts: const Opt[:]) -> Result, const u8[:], const S[:]
fn each_arg<F, S>(argv: const S[:], opts: const Opt[:]) -> Result
fn each_arg_checked<F, S>(argv: const S[:], opts: const Opt[:]) -> Result
fn ok(result: Result) -> bool
fn format_error<S>(out: u8[>..]&, result: Result, argv: const S[:])
fn format_help(out: u8[>..]&, program: const u8[:], opts: const Opt[:], positional: const u8[:] = "")
```

* `argv` is `args()` itself, or any array or slice of `u8[:]` or
  `const u8[:]`, so tests can pass string literals. `argv[0]`, the program,
  is skipped.
* An error is reported at the option's argument, not at a value it took.
* A `return` in an `each_arg` block leaves the function calling `each_arg`.
* `format_error` and `format_help` append text without a final line break,
  as `print` adds one.

## Tests

```bash
goose run test/meiryo_test.goose
python test/abort_test.py
```

`meiryo_test.goose` checks what parsing gives, and `abort_test.py` the
mistakes in the program that abort. An abort stops the program, so
`abort_test.py` runs each of those as a program of its own and checks its
message. It finds goose through `--goose`, the `GOOSE` environment
variable, or `PATH`.

## Not yet

* Options given many times collected into a list (use `each_arg`).
* Negative numbers as positional arguments: `-5` is read as an unknown
  short option. Put `--` before them.
* Required options are left to the program.
