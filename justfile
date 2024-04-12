set shell := ["bash", "-uc"]

gron *args="":
    zig build run -- {{args}}

gron-release *args="":
    zig build run -Doptimize=ReleaseFast -- {{args}}

ungron *args="":
    zig build run -- -u {{args}}

ungron-release *args="":
    zig build run -Doptimize=ReleaseFast -- -u {{args}}


roundtrip file:
    zig build && cat {{file}} | ./zig-out/bin/picogron | ./zig-out/bin/picogron -u

# TODO bench larger json files, or a variety
# huge.json is generated by `node bin/generate-huge-json.mjs testdata/huge.json`
# citylots.json is downloaded from https://github.com/zemirco/sf-city-lots-json/blob/master/citylots.json

bench file *args="":
    zig build -Doptimize=ReleaseFast && poop \
    "./zig-out/bin/picogron {{args}} {{file}}" \

# if perf permission denied: https://github.com/andrewrk/poop/issues/17
# Can `sudo sysctl kernel.perf_event_paranoid=3`
# poop doesn't use shell, so can't use pipes etc.
# Pass -u to test ungron
bench-cmp file *args="":
    zig build -Doptimize=ReleaseFast && poop \
    "./zig-out/bin/picogron {{args}} {{file}}" \
    "fastgron {{args}} {{file}}" \
    "gron {{args}} {{file}}"

# hyperfine uses shell, so can redirect with pipes
bench-cmp-roundtrip file:
    zig build -Doptimize=ReleaseFast && hyperfine \
    "./zig-out/bin/picogron {{file}} | ./zig-out/bin/picogron -u > /dev/null" \
    "fastgron {{file}} | fastgron -u > /dev/null" \
    "gron {{file}} | gron -u > /dev/null"

hyperfine file *args="":
    zig build -Doptimize=ReleaseFast && hyperfine \
    "./zig-out/bin/picogron {{args}} {{file}}" \

hyperfine-cmp file *args="":
    zig build -Doptimize=ReleaseFast && hyperfine \
    "./zig-out/bin/picogron {{args}} {{file}}" \
    "fastgron {{args}} {{file}}" \
    "gron {{args}} {{file}}"

# gron appears to sort differently than `sort`, double check this?
diff-gron file *args="":
    zig build && diff <(./zig-out/bin/picogron {{file}} {{args}} | sort) <(gron {{file}} {{args}} | sort)

# arrays are formatted differently, so need to do compact for both
diff-roundtrip file:
    zig build && diff <(./zig-out/bin/picogron {{file}} | ./zig-out/bin/picogron -u) <(cat {{file}} | jq -c)

test: test-roundtrip test-vs-gron test-vs-gron-stream

test-roundtrip:
    \fd json testdata --exclude "*stream*" --exec just diff-roundtrip

# Test stream separately
test-vs-gron:
    \fd json testdata --exclude "*stream*" --exec just diff-gron

test-vs-gron-stream:
    \fd stream.json testdata --exec just diff-gron --stream

# Test stream separately
#test-vs-ungron:
#    \fd json testdata --exclude "*stream*" --exec just diff-ungron

# can inspect results with `perf report`
perf bin file *args="":
    perf record --call-graph dwarf {{bin}} {{file}} {{args}} > /dev/null

perf-gron file *args="":
    zig build -Doptimize=ReleaseFast && just perf ./zig-out/bin/picogron {{args}} {{file}}

# stackcollapse-perf.pl and flamegraph.pl symlinked into path from flamegraph repo
flamegraph:
    perf script | stackcollapse-perf.pl | flamegraph.pl > perf.svg
