Port of [gron](https://github.com/tomnomnom/gron)

`testdata` is copied from gron at `13561bd`

## Features
- gorn and ungorn
- preserved order for json keys
- minimal parsing
- streaming parsing
- low memory overhead

## Features not planned
- sort
- color
- read directly from url
- values only
- json stream output format
- preserving array indices by inserting null during ungorn

## TODO
- Does gron handle periods in field names? Yes, do this.
- JSON float rendering (requires patch to std lib).
