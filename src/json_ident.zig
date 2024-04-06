const std = @import("std");
const GenCatData = @import("GenCatData");
const code_point = @import("code_point");
const CodePoint = code_point.CodePoint;

pub fn isJsIdent(s: []const u8, gcd: *GenCatData) bool {
    if (s.len == 0 or isReserved(s)) return false;
    var code_points = code_point.Iterator{ .bytes = s };
    var i: usize = 0;
    while (code_points.next()) |cp| : (i += 1) {
        if (i == 0 and !isIdStart(cp.code, gcd)) return false;
        if (i != 0 and !isIdContinue(cp.code, gcd)) return false;
    }
    return true;
}

fn isIdStart(cp: u21, gcd: *GenCatData) bool {
    // gron does not include .Lt titlecase in letters?
    return gcd.gc(cp) == .Lu or
        gcd.gc(cp) == .Ll or
        gcd.gc(cp) == .Lm or
        gcd.gc(cp) == .Lo or
        gcd.gc(cp) == .Nl or
        cp == '$' or cp == '_';
}

fn isIdContinue(cp: u21, gcd: *GenCatData) bool {
    return isIdStart(cp, gcd) or
        gcd.gc(cp) == .Mn or // Mark, Non-Spacing
        gcd.gc(cp) == .Mc or // Mark, Spacing Combining
        gcd.gc(cp) == .Nd or // Number, Decimal Digit
        gcd.gc(cp) == .Pc; // Punctuation, Connector
}

fn isReserved(s: []const u8) bool {
    if (std.meta.stringToEnum(ReservedWords, s)) |_| {
        return true;
    } else {
        return false;
    }
}

// javascript reserved keywords
const ReservedWords = enum {
    @"break",
    case,
    @"catch",
    class,
    @"const",
    @"continue",
    debugger,
    default,
    delete,
    do,
    @"else",
    @"export",
    extends,
    false,
    finally,
    @"for",
    function,
    @"if",
    import,
    in,
    instanceof,
    new,
    null,
    @"return",
    super,
    @"switch",
    this,
    throw,
    true,
    @"try",
    typeof,
    @"var",
    void,
    @"while",
    with,
    yield,
};
