#!/usr/bin/env python3
"""Tests of what meiryo.goose aborts on: mistakes in the program, not in its
arguments. An abort stops the whole program, so each case runs as a program
of its own, and the test checks that it fails with the expected message.

    python test/abort_test.py [--goose path/to/goose]

The goose executable is --goose, else the GOOSE environment variable, else
`goose` on PATH.
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# A spec given to parse_spec, as a Goose string literal.
SPEC_PROGRAM = """\
import std;
import meiryo from "@ROOT@";

fn main() {
    let opts = meiryo::parse_spec(@SPEC@);
    print("parsed ", opts.len);
}
"""

# A table of meiryo::Opt given to each_arg, as a Goose array literal.
TABLE_PROGRAM = """\
import std;
import meiryo from "@ROOT@";

fn main() {
    let opts = @OPTS@;
    var argv: (const u8[:])[>..] = [];
    argv.push("prog");
    meiryo::each_arg(argv, opts) { opt_index, value => print(value); };
    print("parsed");
}
"""

# A spec and the fields of the struct given to parse_into.
STRUCT_PROGRAM = """\
import std;
import meiryo from "@ROOT@";

let SPEC = \"\"\"
    @SPEC@
    \"\"\";

struct Options { @FIELDS@ }

fn main() {
    let opts = meiryo::parse_spec(SPEC);
    var argv: (const u8[:])[>..] = [];
    argv.push("prog");
    var options = Options { .. };
    meiryo::parse_into(options, argv, opts);
    print("parsed");
}
"""


# The same, given to parse_command.
COMMAND_PROGRAM = """\
import std;
import meiryo from "@ROOT@";

let SPEC = \"\"\"
    @SPEC@
    \"\"\";

struct Options { @FIELDS@ }

fn main() {
    let opts = meiryo::parse_spec(SPEC);
    var argv: (const u8[:])[>..] = [];
    argv.push("prog");
    var options = Options { .. };
    meiryo::parse_command(options, argv, opts);
    print("parsed");
}
"""


def spec_case(spec, expected):
    return SPEC_PROGRAM.replace("@SPEC@", spec), expected


def table_case(opts, expected):
    return TABLE_PROGRAM.replace("@OPTS@", opts), expected


def struct_case(spec_lines, fields, expected):
    spec = "\n    ".join(spec_lines)
    return STRUCT_PROGRAM.replace("@SPEC@", spec).replace("@FIELDS@", fields), expected


def command_case(spec_lines, fields, expected):
    spec = "\n    ".join(spec_lines)
    return COMMAND_PROGRAM.replace("@SPEC@", spec).replace("@FIELDS@", fields), expected


# (name, (program, expected)). An expected message is the text after
# "goose runtime error: "; None means the program must run and print
# "parsed", which checks that the harness itself works.
CASES = [
    ("valid spec runs", spec_case('"-v, --verbose  more"', None)),
    ("valid struct runs", struct_case(["-v, --verbose  more", "-f, --frames <N>  n"],
                                      "verbose: bool = false, frames: i64 = -1,", None)),

    # parse_spec: lines not in the form.
    ("short name without long name", spec_case('"-v  more"',
        "meiryo: spec line needs a --long name after -v, every option has one: -v  more")),
    ("short name alone", spec_case('"-v"',
        "meiryo: spec line needs a --long name after -v, every option has one: -v")),
    ("missing comma", spec_case('"-v --verbose  more"',
        "meiryo: spec line needs ',' after -v: -v --verbose  more")),
    ("comma without long name", spec_case('"-v, more"',
        "meiryo: spec line needs a --long name, every option has one: -v, more")),
    ("no dashes", spec_case('"verbose"',
        "meiryo: spec line needs a --long name, every option has one: verbose")),
    ("unclosed value name", spec_case('"--frames <N  more"',
        "meiryo: spec line has '<' without '>': --frames <N  more")),

    # check_opts, through parse_spec and through a table.
    ("space as short name", spec_case('"- , --x  more"',
        "meiryo: option short name is not a visible ASCII character: --x")),
    ("tab as short name", spec_case('"-\\t, --tab  more"',
        "meiryo: option short name is not a visible ASCII character: --tab")),
    ("'=' as short name", spec_case('"-=, --x  more"',
        "meiryo: option short name is '-' or '=': --x")),
    ("'=' in long name", spec_case('"--a=b  more"',
        "meiryo: option long name holds '=': a=b")),
    ("empty long name in a table", table_case('[meiryo::Opt { long: "" }]',
        "meiryo: an option has an empty long name")),
    ("byte 200 as short name in a table", table_case('[meiryo::Opt { long: "high", short: 200 }]',
        "meiryo: option short name is not a visible ASCII character: --high")),
    ("'-' as short name in a table", table_case("[meiryo::Opt { long: \"x\", short: '-' }]",
        "meiryo: option short name is '-' or '=': --x")),

    # check_fields: the struct and the spec disagree.
    ("field without option", struct_case(["-v, --verbose  more"],
        "verbose: bool = false, extra: bool = false,",
        "meiryo: field extra has no option in the spec")),
    ("option without field", struct_case(["-v, --verbose  more", "--gone  x"],
        "verbose: bool = false,",
        "meiryo: option --gone has no field to fill")),
    ("value for a bool field", struct_case(["-v, --verbose <X>  more"],
        "verbose: bool = false,",
        "meiryo: --verbose takes a value, but field verbose is a bool")),
    ("no value for an i64 field", struct_case(["-f, --frames  n"],
        "frames: i64 = -1,",
        "meiryo: field frames needs a value, but --frames has no <VALUE> in the spec")),
    ("field without option, in parse_command", command_case(["-v, --verbose  more"],
        "verbose: bool = false, extra: bool = false,",
        "meiryo: field extra has no option in the spec")),
]


def import_path(directory):
    """The package root as the import line in `directory` names it: relative
    when it can be, with forward slashes, as Goose paths are written."""
    try:
        return Path(os.path.relpath(ROOT, directory)).as_posix()
    except ValueError:  # another drive on Windows
        return ROOT.as_posix()


def find_goose(given):
    goose = given or os.environ.get("GOOSE") or shutil.which("goose")
    if not goose:
        sys.exit("goose not found: pass --goose, set GOOSE, or put goose on PATH")
    return goose


def run_case(goose, directory, index, program, expected):
    """None if the case passed, else what went wrong."""
    source = Path(directory) / f"case_{index}.goose"
    source.write_text(program.replace("@ROOT@", import_path(directory)), encoding="utf-8")
    try:
        run = subprocess.run([goose, "run", str(source)], capture_output=True,
                             text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return "timed out"
    output = run.stdout + run.stderr
    if expected is None:
        if run.returncode != 0 or "parsed" not in run.stdout:
            return f"expected to run, exit {run.returncode}:\n{output}"
        return None
    if run.returncode == 0:
        return f"expected an abort, but it ran:\n{output}"
    if f"goose runtime error: {expected}" not in output:
        return f"expected: goose runtime error: {expected}\ngot (exit {run.returncode}):\n{output}"
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--goose", help="the goose executable")
    goose = find_goose(parser.parse_args().goose)

    failures = 0
    with tempfile.TemporaryDirectory() as directory:
        for index, (name, (program, expected)) in enumerate(CASES):
            problem = run_case(goose, directory, index, program, expected)
            if problem:
                failures += 1
                print(f"FAIL {name}\n  " + problem.rstrip().replace("\n", "\n  "))

    if failures:
        print(f"{failures} of {len(CASES)} cases failed")
        sys.exit(1)
    print(f"all {len(CASES)} cases passed")


if __name__ == "__main__":
    main()
