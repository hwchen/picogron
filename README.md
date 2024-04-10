## Picogron

small code, small memory footprint, small runtime.

Port of [gron](https://github.com/tomnomnom/gron)

The main reason for picogron's existence is to have preserved order for json keys, where gron's keys are either sorted or random.

`testdata` is copied from gron at `13561bd`

## Features
- gron and ungron
- preserved order for json keys
- json stream (line-delimited) input
- minimal parsing. A tree of json values is not produced, instead tokens are handled as they are parsed.
- streaming parsing. Instead of reading an entire input at once, the parser pulls to a buffer incrementally.
- low memory overhead. A result of minimal and streaming parsing, as well as careful usage of allocators only where needed.

## Features not planned
- sort
- color
- read directly from url
- values only
- json stream output format
- preserving array indices by inserting null during ungron

## Development

You'll need zig nightly 2024-04-07 or later to compile picogron. You can [download](https://ziglang.org/download/), or use the nix flake in this repo with `nix develop` (or `direnv allow` if you use `nix-direnv`).
