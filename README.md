Port of [gron](https://github.com/tomnomnom/gron)

The main reason for gorn's existence is to have preserved order for json keys, where gron's keys are either sorted or random.

Features implemented on an as-needed basis, but this will probably stay minimal.

`testdata` is copied from gron at `13561bd`

## Features
- gorn and ungorn
- preserved order for json keys
- minimal parsing. A tree of json values is not produced, instead tokens are handled as they are parsed.
- streaming parsing. Instead of reading an entire input at once, the parser pulls to a buffer incrementally.
- low memory overhead. A result of minimal and streaming parsing, as well as careful usage of allocators only where needed.

## Features not planned
- json stream input (well... maybe if the need comes up)
- sort
- color
- read directly from url
- values only
- json stream output format
- preserving array indices by inserting null during ungorn
- complete support for checking if field names are json identifiers.

## TODO
- Handle escaped quotes in quoted strings when parsing javascript property accessor notation (in ungorn).
