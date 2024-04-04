set shell := ["bash", "-uc"]

gorn file:
    cat {{file}} | zig build run

ungorn file:
    cat {{file}} | zig build run -- -u

roundtrip json-file:
    cat {{json-file}} | zig build run | zig build run -- -u

# arrays are formatted differently, so need to do compact for both
roundtrip-diff json-file:
    zig build && diff <(cat {{json-file}} | ./zig-out/bin/gorn | ./zig-out/bin/gorn -u) <(cat {{json-file}} | jq -c)

roundtrip-test:
    \fd json testdata --exec just roundtrip-diff

# TODO bench larger json files, or a variety
bench-basic:
    zig build -Doptimize=ReleaseSafe && hyperfine \
    "./zig-out/bin/gorn < testdata/big.json > /dev/null" \
    "gron < testdata/big.json > /dev/null"

bench-large-line:
    zig build -Doptimize=ReleaseSafe && hyperfine \
    "./zig-out/bin/gorn < testdata/large-line.json > /dev/null" \
    "gron < testdata/large-line.json > /dev/null"

bench-basic-roundtrip *args="":
    zig build -Doptimize=ReleaseSafe && hyperfine {{args}} \
    "./zig-out/bin/gorn  < testdata/big.json | ./zig-out/bin/gorn -u > /dev/null" \
    "gron  < testdata/big.json | gron -u > /dev/null"

diff-gron file:
    zig build && diff <(cat {{file}} | ./zig-out/bin/gorn | sort) <(gron {{file}} | sort)
