# Contributing

Thanks for helping. This file holds the rules of this repository; please
read it before sending a change.

## Before you send a change

All of these must hold:

```bash
goose run test/meiryo_test.goose     # prints "all N cases passed"
python test/abort_test.py         # prints "all N cases passed"
goose format meiryo.goose examples/*.goose test/*.goose   # leaves no diff
```

* Every change of behavior comes with a test that fails without it.
  Results of parsing go in `test/meiryo_test.goose`; mistakes in the program
  that abort go in `test/abort_test.py` (an abort stops the program, so each
  of those runs as a program of its own).
* Do not change an expected value in a test to make it pass unless the
  change of behavior is intended, and say so in the change's description.
* When the API or a behavior changes, update `README.md`, and check that
  its code examples still compile and run.

## Naming

* **Variables are at least three characters long.** This covers locals,
  parameters, loop variables and block parameters: `arg_index`, not `i`;
  `opt`, not `o`; `{ opt_index, value => ... }`, not `{ k, v => ... }`.
* Avoid names that differ by a letter or two and are used side by side.
  `arg` beside `argv` read as `argv[0]`, so the argument being read is
  `current`.
* Name a variable after what it holds: `opt_name` for an option's name,
  `equals_at` for the position of an `=`.
* Functions follow the standard library's conventions: `each_*` for
  functions that call a block for each item, `format_*` for functions that
  append text to a `u8[>..]`, `parse_*` for the inverse.

## Comments

* Every function in `meiryo.goose` has a comment directly above it saying
  what it does, what it returns, and when it aborts. These `//` lines are
  its documentation (`goose --dump-docs meiryo.goose` lists them), so keep
  them free of blank lines. Overloads of one function share the comment
  above the first of them.
* Comments are full sentences, in English, and say why when the code does
  not show it.
* The comments at the top of `meiryo.goose` and in `README.md` list the
  accepted forms. Keep them in step with the code.

## Design rules

### No copies, no heap

Values are slices into `argv` (or into the spec), never copies. The one
exception is a `u8[>..]` field, which asks for a copy by its type.

### Errors in the arguments, mistakes in the program

* A mistake by the **user of the program** (an unknown option, a missing
  value, a value that is not a number) is returned as a `Result`. It never
  aborts.
* A mistake by the **author of the program** (a malformed spec line, an
  unusable name, a struct that does not match its spec) aborts with a
  message that starts with `meiryo: ` and names the line, option or field.
  Such a message says what is wrong in terms the author can act on: say
  "needs a --long name" rather than "needs ','" when the long name is what
  is missing.
* An error is reported at the option's argument, not at a value it took
  from the next argument.

### Parsing behavior

These are decided; changing them needs a reason and a test.

* `argv[0]` is the program and is skipped.
* Every option has a long name. A short name is optional, and is a visible
  ASCII character other than `-` and `=`.
* An option that takes a value takes the next argument even if it starts
  with `-`.
* Only the first `=` separates a name from its value. After a short name,
  one `=` is dropped, so `-f=3` gives `3` and `-f==3` gives `=3`, as clap
  does.
* `--` makes everything after it positional; a lone `-` is positional.
* Given more than once, an option keeps its last value in `parse_into`.

### Output

`format_*` functions append text without a final line break, because
`print` adds one. To write without a line break, use
`write_stdout(str(...))` from `os`.

### Structure of meiryo.goose

* `parse_spec` and `parse_spec_line` read the spec; `check_opts` checks
  the options.
* `each_arg_checked` walks argv and hands each argument to
  `parse_long` or `parse_short`; both take values through `take_next`.
  `each_arg` and `parse_into` are built on `each_arg_checked`.
* `parse_long` and `parse_short` move `arg_index` only onto a value they
  took. Moving past each argument is done once, at the end of the loop in
  `each_arg_checked`. Keep it that way.
* A new field type for `parse_into` needs an overload of both
  `field_takes_value` and `assign_field`, a row in the README's table, and
  a test.

## Goose details worth knowing

* `const u8[:][:]` is `(const u8[:])[:]`: the `const` applies to the inner
  slices. A parameter that takes both `args()` and an array of string
  literals is written `const S[:]` with a type parameter `S`.
* A `return` inside a block leaves the function where the block was
  written, through every function that called the block.
* There are no variadic functions outside the builtins (`print`, `str`,
  `format`).
* A struct with a `const u8[:]` field filled from `argv` must be declared
  after `argv`.
