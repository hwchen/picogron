roundtrip json-file:
    cat {{json-file}} | zig build run | zig build run -- -u

# arrays are formatted differently, so need to do compact for both
roundtrip-diff json-file:
    zig build && diff <(cat {{json-file}} | ./zig-out/bin/gorn | ./zig-out/bin/gorn -u) <(cat {{json-file}} | jq -c)
