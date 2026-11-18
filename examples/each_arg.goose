// An example of each_arg, the lower level under parse_into: the options as
// a table of meiryo::Opt, and a block that sees each argument. Use it when a
// struct does not fit, e.g. for an option that may be given many times.
//
//   goose run examples/each_arg.goose -- --frames 10 -v map1.wad map2.wad
//   goose run examples/each_arg.goose -- --help

import std;
import os;
import meiryo from "..";

fn main() {
    let opts = [
        meiryo::Opt { long: "help", short: 'h', help: "show this help" },
        meiryo::Opt { long: "silent", short: 's', help: "print nothing while running" },
        meiryo::Opt { long: "verbose", short: 'v', help: "print more" },
        meiryo::Opt { long: "frames", short: 'f', takes_value: true, value_name: "N", help: "stop after N frames" },
        meiryo::Opt { long: "name", takes_value: true, help: "a name to greet" },
    ];

    let argv = args();
    var help = false;
    var quiet = false;
    var verbose = false;
    var frames = -1;
    var name:  u8[>..]            = [];
    var files: (const u8[:])[>..] = [];
    var bad:   u8[>..]            = [];

    let result = meiryo::each_arg(argv, opts) { opt_index, value =>
        if opt_index < 0 {
            files.push(value);
        } else {
            let opt_name = opts[opt_index].long;
            if opt_name == "help" {
                help = true;
            }
            if opt_name == "silent" {
                quiet = true;
            }
            if opt_name == "verbose" {
                verbose = true;
            }
            if opt_name == "name" {
                name.append(value);
            }
            if opt_name == "frames" {
                let count, parsed = parse_int(value);
                if parsed && count >= 0 {
                    frames = count;
                } else if bad.len == 0 {
                    format(bad, "--frames needs a number, got ", value);
                }
            }
        }
    };

    guard meiryo::ok(result) else {
        var msg: u8[>..] = [];
        meiryo::format_error(msg, result, argv);
        print("error: ", msg);
        return;
    }
    if bad.len > 0 {
        print("error: ", bad);
        return;
    }
    if help {
        var out: u8[>..] = [];
        meiryo::format_help(out, "each_arg", opts, "<file>...");
        print(out);
        return;
    }

    print("quiet=", quiet, " verbose=", verbose, " frames=", frames, " name=", name);
    print("files=", files);
}
