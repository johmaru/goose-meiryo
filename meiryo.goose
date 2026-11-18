// A small command line parser. The options are written as a spec, one per
// line, in the form the help prints them:
//
//   -f, --frames <N>    stop after N frames
//
// parse_spec turns the spec into a table of Opt, and parse_into fills a
// struct whose fields are named after the options. Underneath, each_arg
// hands every option and positional argument to a block as slices into
// argv, so nothing is copied. parse_command reads the options before a
// command and splits argv at the command, for programs with subcommands.
//
// Accepted forms:
//   --name          a flag
//   --name=value    an option with its value in the same argument
//   --name value    an option with its value in the next argument
//   -n              a flag by its short name
//   -abc            several short flags at once
//   -nvalue, -n v   a short option with its value
//   -n=value        the same; one "=" right after the name is dropped
//   --              everything after it is positional
// A lone "-" is positional, as is anything not starting with "-".
// Only the first "=" separates, so a value starting with "=" is written
// --name==value or -n==value.

namespace meiryo;

import std;

struct Opt {
    const long: u8[:],                  // the name after "--", e.g. "frames"
    short:       u8   = 0,              // the letter after "-", e.g. 'f'; 0 for none
    takes_value: bool = false,
    const value_name: u8[:] = "VALUE",  // shown in the help: --frames <N>
    const help:       u8[:] = "",
}

enum Error {
    None,
    UnknownOption,
    MissingValue,        // an option that takes a value came last
    UnexpectedValue,     // --flag=value for a flag that takes none
    BadValue,            // a value the block refused, e.g. not a number
    UnexpectedArgument,  // a positional argument the block refused
}

// What went wrong, and at which index of the argv that was parsed (for a
// command, its sub_argv). `at` is -1 when nothing did.
struct Result {
    error: Error = Error.None,
    at:    i64   = -1,
}

// Whether each_arg, parse_into or parse_command went through argv without an
// error.
fn ok(result: Result) -> bool {
    result.error == Error.None
}

// ---------------------------------------------------------------------------
// The spec.

// The options in `spec`, one per line, in the form
//
//   [-x, ]--long[ <VALUE>][ help text]
//
// Leading and trailing spaces and blank lines are ignored. A <VALUE> makes
// the option take a value, shown under that name in the help. The Opts are
// slices of `spec`, so it must outlive them, which a string literal always
// does. Aborts, naming the line, on a line not in this form.
fn parse_spec(spec: const u8[:]) -> Opt[>..] {
    var opts: Opt[>..] = [];
    each_split(spec, '\n') { raw_line =>
        let line = trim(raw_line);
        if line.len > 0 {
            opts.push(parse_spec_line(line));
        }
    };
    check_opts(opts);
    return opts;
}

// The index of the first byte at or after `pos` that is not a space or tab.
fn skip_spaces(line: const u8[:], pos: i64) -> i64 {
    var end = pos;
    while end < line.len && (line[end] == ' ' || line[end] == '\t') {
        end++;
    }
    end
}

// One line of a spec, trimmed and not empty.
fn parse_spec_line(line: const u8[:]) -> Opt {
    var pos = 0;
    var short: u8 = 0;
    if line.len >= 2 && line[0] == '-' && line[1] != '-' {
        short = line[1];
        if line.len < 3 || line[2] != ',' {
            // Tell a missing comma ("-v --verbose") from a missing long name ("-v  help").
            if starts_with(line[skip_spaces(line, 2)..], "--") {
                abort(str("meiryo: spec line needs ',' after -", line[1..2], ": ", line));
            }
            abort(str("meiryo: spec line needs a --long name after -", line[1..2], ", every option has one: ", line));
        }
        pos = skip_spaces(line, 3);
    }
    if !starts_with(line[pos..], "--") {
        abort(str("meiryo: spec line needs a --long name, every option has one: ", line));
    }
    let name_start = pos + 2;
    var name_end = name_start;
    while name_end < line.len && line[name_end] != ' ' && line[name_end] != '\t' {
        name_end++;
    }
    pos = skip_spaces(line, name_end);
    var takes_value = false;
    var value_name: const u8[:] = "VALUE";
    if pos < line.len && line[pos] == '<' {
        let close = position(line[pos..], '>');
        if close < 0 {
            abort(str("meiryo: spec line has '<' without '>': ", line));
        }
        value_name = line[pos + 1..pos + close];
        takes_value = true;
        pos = skip_spaces(line, pos + close + 1);
    }
    Opt {
        long:        line[name_start..name_end],
        short:       short,
        takes_value: takes_value,
        value_name:  value_name,
        help:        line[pos..],
    }
}

// Aborts, naming the option, if `opts` holds one that no argument could
// reach: an empty long name, a long name holding "=", or a short name that
// is not a visible ASCII character, or is "-" or "=". These are mistakes in
// the program, not in its arguments.
fn check_opts(opts: const Opt[:]) {
    for opt in opts {
        if opt.long.len == 0 {
            abort("meiryo: an option has an empty long name");
        }
        if position(opt.long, '=') >= 0 {
            abort(str("meiryo: option long name holds '=': ", opt.long));
        }
        if opt.short != 0 && (opt.short <= ' ' || opt.short >= 127) {
            abort(str("meiryo: option short name is not a visible ASCII character: --", opt.long));
        }
        if opt.short == '-' || opt.short == '=' {
            abort(str("meiryo: option short name is '-' or '=': --", opt.long));
        }
    }
}

// ---------------------------------------------------------------------------
// Reading argv.

// The index in `opts` of the option named `name` after "--", or -1.
fn find_long(opts: const Opt[:], name: const u8[:]) -> i64 {
    for opt, index in opts {
        if opt.long == name {
            return index;
        }
    }
    -1
}

// The index in `opts` of the option with the short name `letter`, or -1.
fn find_short(opts: const Opt[:], letter: u8) -> i64 {
    for opt, index in opts {
        if opt.short != 0 && opt.short == letter {
            return index;
        }
    }
    -1
}

// The argument after argv[arg_index], as an option's value, moving
// arg_index onto it. False, with arg_index unchanged, if there is none.
fn take_next<S>(argv: const S[:], arg_index: i64&) -> const u8[:], bool {
    if arg_index + 1 >= argv.len {
        return "", false;
    }
    arg_index++;
    let value: const u8[:] = argv[arg_index];
    return value, true;
}

// Handles "--name" or "--name=value" at argv[arg_index], calling F for it.
// If the option's value is the next argument, moves arg_index onto it.
fn parse_long<F, S>(argv: const S[:], opts: const Opt[:], arg_index: i64&) -> Error {
    let current: const u8[:] = argv[arg_index];
    let body = current[2..];
    let equals_at = position(body, '=');
    let name = if equals_at >= 0 {
        body[..equals_at]
    } else {
        body
    };
    let opt_index = find_long(opts, name);
    if opt_index < 0 {
        return Error.UnknownOption;
    }
    if !opts[opt_index].takes_value {
        if equals_at >= 0 {
            return Error.UnexpectedValue;
        }
        if !F(opt_index, "") {
            return Error.BadValue;
        }
        return Error.None;
    }
    if equals_at >= 0 {
        if !F(opt_index, body[equals_at + 1..]) {
            return Error.BadValue;
        }
        return Error.None;
    }
    let value, found = take_next(argv, arg_index);
    if !found {
        return Error.MissingValue;
    }
    if !F(opt_index, value) {
        return Error.BadValue;
    }
    Error.None
}

// Handles one or more short names after a single "-" at argv[arg_index]:
// "-v", "-sv", "-f3", "-f=3", or "-f" with its value in the next argument,
// calling F for each. If a value is the next argument, moves arg_index
// onto it.
fn parse_short<F, S>(argv: const S[:], opts: const Opt[:], arg_index: i64&) -> Error {
    let current: const u8[:] = argv[arg_index];
    var char_index = 1;
    while char_index < current.len {
        let opt_index = find_short(opts, current[char_index]);
        if opt_index < 0 {
            return Error.UnknownOption;
        }
        if opts[opt_index].takes_value {
            // The rest of the argument is the value: -f3 and -f=3 both give "3".
            if char_index + 1 < current.len {
                var value_at = char_index + 1;
                if current[value_at] == '=' {
                    value_at++;
                }
                if !F(opt_index, current[value_at..]) {
                    return Error.BadValue;
                }
                return Error.None;
            }
            let value, found = take_next(argv, arg_index);
            if !found {
                return Error.MissingValue;
            }
            if !F(opt_index, value) {
                return Error.BadValue;
            }
            return Error.None;
        }
        if !F(opt_index, "") {
            return Error.BadValue;
        }
        char_index++;
    }
    Error.None
}

// each_arg, with a block that returns whether it accepts what it was given:
// false stops with BadValue for an option and UnexpectedArgument for a
// positional argument, reported at that argument.
fn each_arg_checked<F, S>(argv: const S[:], opts: const Opt[:]) -> Result {
    check_opts(opts);
    var arg_index = 1;
    var only_positional = false;
    while arg_index < argv.len {
        let current: const u8[:] = argv[arg_index];
        // parse_long and parse_short move arg_index only onto a value they
        // took; moving past each argument is done here, at the end.
        let start = arg_index;
        var error = Error.None;
        if only_positional || current.len < 2 || current[0] != '-' {
            if !F(-1, current) {
                error = Error.UnexpectedArgument;
            }
        } else if current == "--" {
            only_positional = true;
        } else if starts_with(current, "--") {
            error = parse_long(argv, opts, arg_index, F);
        } else {
            error = parse_short(argv, opts, arg_index, F);
        }
        // An error is reported at the option, not at a value it took.
        if error != Error.None {
            return Result { error: error, at: start };
        }
        arg_index++;
    }
    Result { error: Error.None, at: -1 }
}

// F(index, value) for each argument after argv[0], in order. `index` is the
// option's position in `opts`, or -1 for a positional argument. `value` is
// the option's value ("" for a flag), or the positional argument itself.
//
// Stops at the first bad argument, which F does not see, and returns what
// went wrong and where. A block's `return` leaves the function calling
// each_arg, as with csv::each_record. Aborts if `opts` holds an option no
// argument could reach (check_opts).
//
// `argv` is args() itself, or any array or slice of byte slices, writable
// (u8[:]) or not (const u8[:]), so a test can pass string literals.
fn each_arg<F, S>(argv: const S[:], opts: const Opt[:]) -> Result {
    return each_arg_checked(argv, opts) { opt_index, value =>
        F(opt_index, value);
        true
    };
}

// ---------------------------------------------------------------------------
// Filling a struct.

// The field types parse_into fills, and whether the option for each takes
// a value: a bool field is a flag, every other field takes one.
fn field_takes_value(field: bool&) -> bool {
    false
}
fn field_takes_value(field: i64&) -> bool {
    true
}
fn field_takes_value(field: f64&) -> bool {
    true
}
fn field_takes_value(field: (const u8[:])&) -> bool {
    true
}
fn field_takes_value(field: u8[>..]&) -> bool {
    true
}

// Stores `value` in a field of each type parse_into fills, false if the
// text is not a value of that type: a flag is set to true, a number is
// parsed, and text is kept as a slice or copied into a u8[>..].
fn assign_field(field: bool&, value: const u8[:]) -> bool {
    field = true;
    true
}

fn assign_field(field: i64&, value: const u8[:]) -> bool {
    let number, parsed = parse_int(value);
    if parsed {
        field = number;
    }
    parsed
}

fn assign_field(field: f64&, value: const u8[:]) -> bool {
    let number, parsed = parse_flt(value);
    if parsed {
        field = number;
    }
    parsed
}

fn assign_field(field: (const u8[:])&, value: const u8[:]) -> bool {
    field = value;
    true
}

fn assign_field(field: u8[>..]&, value: const u8[:]) -> bool {
    field.clear();
    field.append(value);
    true
}

// Whether the option named `long` is the one for the field named
// `field_name`: the same name, with each '-' of the option a '_' in the
// field, so --dry-run fills dry_run.
fn names_match(long: const u8[:], field_name: const u8[:]) -> bool {
    if long.len != field_name.len {
        return false;
    }
    for letter, index in long {
        let other = field_name[index];
        if letter != other && !(letter == '-' && other == '_') {
            return false;
        }
    }
    true
}

// Aborts, naming it, on a field of T with no option in `opts`, an option
// with no field, or an option whose spec line and field disagree on
// whether it takes a value. These are mistakes in the program.
fn check_fields<T>(target: T&, opts: const Opt[:]) {
    const for <N, A> in fields<T> {
        var found = false;
        for opt in opts {
            if names_match(opt.long, N) {
                found = true;
                let wanted = field_takes_value(target.A);
                if opt.takes_value && !wanted {
                    abort(str("meiryo: --", opt.long, " takes a value, but field ", N, " is a bool"));
                }
                if !opt.takes_value && wanted {
                    abort(str("meiryo: field ", N, " needs a value, but --", opt.long, " has no <VALUE> in the spec"));
                }
            }
        }
        if !found {
            abort(str("meiryo: field ", N, " has no option in the spec"));
        }
    }
    for opt in opts {
        var found = false;
        const for <N, A> in fields<T> {
            if names_match(opt.long, N) {
                found = true;
            }
        }
        if !found {
            abort(str("meiryo: option --", opt.long, " has no field to fill"));
        }
    }
}

// Stores `value` in the field of `target` for the option named `long`.
fn assign_option<T>(target: T&, long: const u8[:], value: const u8[:]) -> bool {
    const for <N, A> in fields<T> {
        if names_match(long, N) {
            return assign_field(target.A, value);
        }
    }
    false
}

// Fills `target`, a struct with one field per option named after it
// (names_match), from argv: a bool field becomes true when its flag is
// given, an i64 or f64 field takes the parsed value, and a const u8[:] or
// u8[>..] field the text. Fields of options not given keep their values, so
// give them defaults. Positional arguments are pushed onto `positional`.
//
// Stops at the first bad argument and returns what went wrong and where:
// BadValue when a value does not parse as its field's type. Aborts if T
// and `opts` do not match (check_fields). A const u8[:] field holds a slice
// of argv, so declare `target` after argv.
fn parse_into<T, S>(target: T&, argv: const S[:], opts: const Opt[:], positional: (const u8[:])[>..]&) -> Result {
    check_fields(target, opts);
    return each_arg_checked(argv, opts) { opt_index, value =>
        if opt_index < 0 {
            positional.push(value);
            true
        } else {
            assign_option(target, opts[opt_index].long, value)
        }
    };
}

// parse_into for a program that takes no positional arguments: one is
// reported as UnexpectedArgument.
fn parse_into<T, S>(target: T&, argv: const S[:], opts: const Opt[:]) -> Result {
    check_fields(target, opts);
    return each_arg_checked(argv, opts) { opt_index, value =>
        opt_index >= 0 && assign_option(target, opts[opt_index].long, value)
    };
}

// Reads the options before the command into `target`, as parse_into does,
// and splits argv at the command: the first positional argument. An option's
// value is never the command. A `--` before the command only ends the global
// options, so it makes a command that starts with `-` possible; a `--` meant
// for the command goes after the command. Returns the result, the command,
// and the arguments from the command on, so sub_argv[0] is the command's
// name and the arguments can be handed to parse_command or parse_into again. With no command, or on an error, the command is "" and
// the arguments are empty. Report an error of the command's own parsing with
// the arguments it parsed, not with argv. Aborts if T and `opts` do not
// match (check_fields). The command and the arguments are slices of argv.
fn parse_command<T, S>(target: T&, argv: const S[:], opts: const Opt[:]) -> Result, const u8[:], const S[:] {
    let result = parse_into(target, argv, opts);
    if result.error == Error.UnexpectedArgument {
        // The command is the argument parse_into would not take.
        return Result {}, argv[result.at], argv[result.at..];
    }
    return result, "", argv[argv.len..];
}

// ---------------------------------------------------------------------------
// Messages.

// Appends a message for a failed each_arg, parse_into or parse_command to
// `out`, without a line break. `argv` is the one that was parsed.
fn format_error<S>(out: u8[>..]&, result: Result, argv: const S[:]) {
    if result.error == Error.None {
        return;
    }
    let arg: const u8[:] = argv[result.at];
    if result.error == Error.UnknownOption {
        format(out, "unknown option: ", arg);
    }
    if result.error == Error.MissingValue {
        format(out, "missing value for ", arg);
    }
    if result.error == Error.UnexpectedValue {
        format(out, "option takes no value: ", arg);
    }
    if result.error == Error.BadValue {
        format(out, "invalid value for ", arg);
    }
    if result.error == Error.UnexpectedArgument {
        format(out, "unexpected argument: ", arg);
    }
}

// Appends a usage line and one line per option to `out`, the lines
// separated by line breaks and the last without one, as print adds it.
// `positional` describes the positional arguments in the usage line, e.g.
// "<file>...".
fn format_help(out: u8[>..]&, program: const u8[:], opts: const Opt[:], positional: const u8[:] = "") {
    format(out, "usage: ", program, " [options]");
    if positional.len > 0 {
        format(out, " ", positional);
    }
    let column = 28;
    for opt in opts {
        out.push('\n');
        let start = out.len;
        if opt.short != 0 {
            out.append("  -");
            out.push(opt.short);
            out.append(", ");
        } else {
            out.append("      ");
        }
        format(out, "--", opt.long);
        if opt.takes_value {
            format(out, " <", opt.value_name, ">");
        }
        if out.len - start >= column {
            out.push(' ');
        }
        while out.len - start < column {
            out.push(' ');
        }
        out.append(opt.help);
    }
}
