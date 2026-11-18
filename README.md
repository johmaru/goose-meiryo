# meiryo

*meiryo* (明瞭) is Japanese for "clear, easy to understand".

meiryo is a small command line parser for
[Goose](https://github.com/aardappel/goose). You write the options as a
spec that looks like the output of `--help`, and meiryo reads the arguments
into a struct with one field per option. Values are slices into `argv`;
meiryo copies a value only when a field's type asks for a copy.

## Using it

Import the package in your program's root file:

```goose
import meiryo from "github.com/johmaru/goose-meiryo@v0.1.0";  // a tagged version
import meiryo from "../path/to/this/directory";                // or a local checkout
```

A minimal program:

```goose
import std;
import os;
import meiryo from "github.com/johmaru/goose-meiryo@v0.1.0";

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

Each line of the spec describes one option:

```
[-x, ]--long[ <VALUE>][ help text]
```

* `--long` is required. `-x, ` adds a short name.
* `<VALUE>` makes the option take a value. The help shows the value under
  that name.
* meiryo ignores leading spaces and blank lines, so you can indent a `"""`
  raw string with the code around it.
* Because the `Opt`s that `parse_spec` returns are slices of the spec, the
  spec must outlive them. A string literal always does.

## The struct

Each field has the name of its option, with every `-` written as `_`:
`--dry-run` fills `dry_run`. A field keeps its value when its option is
absent, so give every field a default.

| Field type | Option | Value stored |
|---|---|---|
| `bool` | a flag (no `<VALUE>`) | `true` when given |
| `i64` | takes a value | `parse_int` of the text, or `BadValue` |
| `f64` | takes a value | `parse_flt` of the text, or `BadValue` |
| `const u8[:]` | takes a value | the text, a slice of `argv` |
| `u8[>..]` | takes a value | a copy of the text |

A field of any other type is a compile error. An option given more than
once keeps its last value. A `const u8[:]` field holds a slice of `argv`,
so declare the struct after `argv`.

`parse_into` pushes positional arguments onto its last argument. A program
that takes no positional arguments may leave that argument out; a
positional argument is then an `UnexpectedArgument` error.

## Mistakes in the program

Because these are bugs in the program, not in its arguments, meiryo aborts
with a message that names the option, field, or spec line:

* a spec line not in the form above;
* an empty long name, or a long name that contains `=`;
* a short name that is not a visible ASCII character, or is `-` or `=`;
* a field with no option in the spec, or an option with no field;
* a `bool` field whose spec line has a `<VALUE>`, or a field of another
  type whose spec line has none.

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

An option that takes a value always takes the next argument, even when it
starts with `-`: `--frames --silent` gives `--frames` the value `--silent`.

Only the first `=` separates the name from the value. To pass a value that
starts with `=`, write `--frames==3` or `-f==3`; both give `=3`, as clap
does.

## The lower level: each_arg

When a struct does not fit, such as for an option given many times,
`each_arg` calls a block for each argument:

```goose
let result = meiryo::each_arg(argv, opts) { opt_index, value =>
    if opt_index < 0 {
        files.push(value);        // a positional argument
    } else if opts[opt_index].long == "include" {
        includes.push(value);
    }
};
```

`opts` may come from `parse_spec` or be a table of `meiryo::Opt` written by
hand. `each_arg_checked` works the same way, but its block returns a
`bool`: `false` rejects the value (`BadValue`) or the positional argument
(`UnexpectedArgument`). `examples/each_arg.goose` is a complete program.

## Subcommands

For a program with commands, such as `git remote add`, `parse_command`
reads the options before the command into a struct and splits argv at the
command:

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
  taken as the command.
* A `--` before the command ends only the global options, so the command
  may then start with `-`. To pass `--` to the command, put it after the
  command: `prog run -- --weird-file`.
* `parse_command` stops at the command. `sub_argv` is argv from the command
  on, so `sub_argv[0]` is the command's name and the options after it are
  the command's own. Pass `sub_argv` to `parse_into` to read them, or to
  `parse_command` again for a command with commands of its own.
* With no command, or on an error, `command` is `""` and `sub_argv` is
  empty. The program must report an unknown command itself.
* Because an error from parsing `sub_argv` has an `at` that counts in
  `sub_argv`, pass `sub_argv`, not `argv`, to `format_error`.

`examples/subcommand.goose` is a complete program. It has a command under
a command, and a `--help` that lists the commands.

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
  `const u8[:]`, so tests can pass string literals. meiryo skips
  `argv[0]`, the program.
* An error points at the option's argument, not at a value it took.
* A `return` in an `each_arg` block leaves the function that called
  `each_arg`.
* `format_error` and `format_help` append text without a final line break,
  because `print` adds one.

## Tests

```bash
goose run test/meiryo_test.goose
python test/abort_test.py
```

`meiryo_test.goose` checks the results of parsing. `abort_test.py` checks
the mistakes in the program that abort. Because an abort stops the
program, `abort_test.py` runs each case as a program of its own and checks
its message. It finds goose through `--goose`, the `GOOSE` environment
variable, or `PATH`.

## Not yet

* Lists for options given many times: use `each_arg` for now.
* Negative numbers as positional arguments: meiryo reads `-5` as an
  unknown short option. Put `--` before them.
* Required options: the program must check them itself.
