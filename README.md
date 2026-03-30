## Picogron

Reimplementation of [gron](https://github.com/tomnomnom/gron), focusing on small code, small memory footprint, small runtime.

The main reason for picogron's existence is to have preserved order for json keys, where gron's keys are either sorted or random.

The focus on small memory footprint means simd-json approaches will win at turning larger json files into gron (like [fastgron](https://github.com/adamritter/fastgron)). On the other hand, picogron performs extremely well on smaller json inputs, as well as ungron for small and large files.

`testdata` is copied from gron at `13561bd`

## Features
- gron and ungron
- preserved order for json keys
- json stream (line-delimited) input
- minimal parsing. A tree of json values is not produced, instead tokens are handled as they are parsed.
- streaming parsing. Instead of reading an entire input at once, the parser pulls data incrementally.
- low memory overhead. A result of minimal and streaming parsing, as well as careful usage of allocators only where needed.

## Usage
```
Transform JSON (from a file or stdin) into discrete assignments to make it greppable

Usage:
  picogron [OPTIONS] [FILE]

positional arguments:
  FILE           file name (stdin if no filename provided)

options:
  -h, --help     show this help message and exit
  -s, --stream   enable stream mode for json input (line delimited)
  -u, --ungron   ungron: convert gron output back to JSON
```

## Features not planned
- sort
- color
- read directly from url
- values only
- json stream output format

Note: semicolons are always output, and ungron expects semicolons in the input. TODO better error messages for this.

### Ungron note

When GRON input skips around hierarchy, `picogron -u` does not coalesce objects or arrays.

For example,
```
json.a.b = "one";
json.c = "two";
json.a.d = "three";
```

With gron, becomes
```
{
  "a": {
    "b": "one",
    "d": "three"
  },
  "c": "two"
}
```

while picogron becomes
```
{"a":{"b":"one"},"c":"two","a":{"d":"three"}}
```

Picogron's streaming-in-order model does not allow skipping around.

And, I imagine that basic cases of `picogron | grep | picogron -u` should always contain hierarchies in the right order.

(Perhaps a use case would be appending a second input? If this is more common than I think, let me know (and also perhaps why gron-style is preferred over jq-style))

## Development

You'll need zig 0.14 to compile picogron. You can [download](https://ziglang.org/download/).

For some tests, you may need to install the [turnt](https://github.com/cucapra/turnt) test framework.
