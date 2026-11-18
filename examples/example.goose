// An example of meiryo.goose: the options of samples/31_mini_doom.goose plus a
// few more, written as a spec and read into a struct.
//
//   goose run examples/example.goose -- --frames 10 -v map1.wad map2.wad
//   goose run examples/example.goose -- --help

import std;
import os;
import meiryo from "..";

// The options, as --help prints them.
let SPEC = """
    -h, --help          show this help
    -s, --silent        print nothing while running
    -v, --verbose       print more
    -f, --frames <N>    stop after N frames
        --name <NAME>   a name to greet
    """;

// One field per option, named after it, holding the value it keeps when
// the option is not given.
struct Options {
    help:    bool        = false,
    silent:  bool        = false,
    verbose: bool        = false,
    frames:  i64         = -1,
    name:    const u8[:] = "",
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
        meiryo::format_help(help, "example", opts, "<file>...");
        print(help);
        return;
    }
    if options.frames < -1 {
        print("error: --frames needs a count of 0 or more");
        return;
    }

    print("silent=", options.silent, " verbose=", options.verbose, " frames=", options.frames, " name=", options.name);
    print("files=", files);
}
