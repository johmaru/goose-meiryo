# Notes for coding agents

This repository is `meiryo`, a command line parser package for
[Goose](https://github.com/aardappel/goose). The rules for every change are
in [CONTRIBUTING.md](CONTRIBUTING.md); read it first and follow it. This
file adds what an agent in particular should do.

## How the maintainer works

* The maintainer reads and checks the code. Write code that is easy to
  read over code that is short, and explain changes so they can be
  checked.
* Ask before changing a public name (`Opt`, `Result`, `parse_into`,
  `each_arg` and the rest of the API in `README.md`) or a parsing behavior
  listed in `CONTRIBUTING.md`. Fixing a bug or a misleading message does not
  need asking, but say what changed.
* Do not publish, tag or push.

## Verify, do not assume

* Goose is new and changes. Do not write Goose from memory of other
  languages: check `docs/goose_spec.md` and the standard library in the
  Goose repository, and compile what you write.
* Before saying a change is done, run both test suites and `goose format`
  as `CONTRIBUTING.md` shows, and report their results. If you could not
  run something, say so.
* When a test is added, check that it can fail: break the code or the
  expectation in a copy and see the test report it.
* README code examples are not compiled by the tests. When you change one,
  extract it and run it.

## Getting goose

If `goose` is not installed, build it from source:

```bash
git clone https://github.com/aardappel/goose
cd goose
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
```

It needs CMake 3.27 or later and a C++20 compiler. The compiler is
`build/goose` (`build/Release/goose.exe` with Visual Studio). Pass it to
`test/abort_test.py` with `--goose`.

## Brace style

* Put the body of every block on its own lines, even when it is one
  statement. `goose format` keeps either form, so it will not do this for
  you.
* Use K&R style: the opening brace ends the line that starts the block,
  and the closing brace stands on a line of its own.

```goose
if line.len == 0 {
    return;
}
```

Not `if line.len == 0 { return; }`, and not the brace on the next line:

```goose
if line.len == 0
{
    return;
}
```

## Naming

`CONTRIBUTING.md` has the naming rules. In addition:

* One name means one kind of thing across the whole file. If a name holds
  the field itself in one function (`field: i64&`), do not use it in
  another for the field's name (`field: const u8[:]`). Call that one
  `field_name`. A reader who has learned what a name means in one function
  should not have to learn it again in the next.
* Do not give a variable or parameter the name of a language feature it is
  not, such as `fields` for something other than what `fields<T>` gives.

## Pitfalls seen in this repository

* A message that names the wrong cause sends the author the wrong way. For
  an abort, test the message, not only that it aborts.
* Character checks must cover more than the obvious cases: a space, a tab
  and bytes of 127 and above were once accepted as short names.
* `meiryo_test.goose` builds argv by splitting a line at spaces, so an empty
  line gives an empty positional argument. Do not write a case with an
  empty line.
