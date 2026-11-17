//! Teste de mutação: altera um detalhe do código (um operador, um `return`),
//! roda os testes e confere se algum falha. Mutante que sobrevive é
//! comportamento sem teste.
const std = @import("std");
const Ast = std.zig.Ast;
const source = @import("source.zig");
const Parsed = source.Parsed;

pub const Report = struct {
    pub const Survivor = struct { path: []const u8, line: u32, column: u32 = 0, description: []const u8 };
    pub const Place = struct { path: []const u8, line: u32 };

    /// Os testes passam sem mutação? Se não, nada mais foi medido.
    baseline_ok: bool,
    killed: u32 = 0,
    timeout: u32 = 0,
    no_compile: u32 = 0,
    disabled: u32 = 0,
    survivors: []const Survivor = &.{},
    /// `// mutation: disable` sem motivo: não desativa nada e reprova.
    missing_reason: []const Place = &.{},
};

/// Uso: mutate <zig> <pasta src> <raiz dos testes, relativa a src> <pasta de trabalho> <saída .zon> <segundos por mutante>
///
/// Copia `src/` para a pasta de trabalho e muta só a cópia: o código original
/// nunca é alterado, mesmo se o processo for interrompido.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 7) return error.Usage;
    const runner: Runner = .{
        .arena = arena,
        .io = io,
        .zig = args[1],
        .test_root = args[3],
        .workspace = args[4],
        .timeout_seconds = args[6],
    };
    const files = try source.readZigFiles(arena, io, args[2]);
    const report = try runner.run(files);
    try source.writeZon(arena, io, args[5], report);
}

const Runner = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    zig: []const u8,
    test_root: []const u8,
    workspace: []const u8,
    timeout_seconds: []const u8,

    fn run(self: Runner, files: []const source.SourceFile) !Report {
        for (files) |f| try self.write(f.path, f.source);
        if (try self.runTests() != .survived) return .{ .baseline_ok = false };

        var report: Report = .{ .baseline_ok = true };
        var survivors: std.ArrayList(Report.Survivor) = .empty;
        var missing: std.ArrayList(Report.Place) = .empty;
        for (files) |f| {
            if (source.isScreenCode(f.path)) continue;
            const p: Parsed = try .init(self.arena, f.source);
            const ds = try directives(self.arena, f.source);
            for (ds) |d| {
                if (!d.has_reason) try missing.append(self.arena, .{ .path = f.path, .line = d.line });
            }
            for (try mutants(self.arena, p)) |m| {
                if (isDisabled(ds, m.line)) {
                    report.disabled += 1;
                    continue;
                }
                try self.write(f.path, try apply(self.arena, f.source, m));
                switch (try self.runTests()) {
                    .killed => report.killed += 1,
                    .timeout => report.timeout += 1,
                    .no_compile => report.no_compile += 1,
                    .survived => try survivors.append(self.arena, .{ .path = f.path, .line = m.line, .column = m.column, .description = m.description }),
                }
            }
            try self.write(f.path, f.source);
        }
        report.survivors = survivors.items;
        report.missing_reason = missing.items;
        return report;
    }

    fn write(self: Runner, path: []const u8, data: []const u8) !void {
        var ws = try std.Io.Dir.cwd().openDir(self.io, self.workspace, .{});
        defer ws.close(self.io);
        if (std.fs.path.dirnamePosix(path)) |dir| try ws.createDirPath(self.io, dir);
        try ws.writeFile(self.io, .{ .sub_path = path, .data = data });
    }

    fn runTests(self: Runner) !Outcome {
        const result = try std.process.run(self.arena, self.io, .{
            .argv = &.{ "timeout", self.timeout_seconds, self.zig, "test", self.test_root },
            .cwd = .{ .path = self.workspace },
        });
        return classify(result.term, result.stderr);
    }
};

/// Uma alteração no código: trocar os bytes `[start, end)` por `replacement`.
pub const Mutant = struct {
    start: u32,
    end: u32,
    replacement: []const u8,
    line: u32,
    column: u32 = 0,
    /// Ex.: "`<` → `<=`".
    description: []const u8,
};

/// Todos os mutantes do arquivo, fora dos blocos `test`.
pub fn mutants(gpa: std.mem.Allocator, p: Parsed) ![]Mutant {
    const tree = p.tree;
    var list: std.ArrayList(Mutant) = .empty;
    errdefer list.deinit(gpa);
    var t: Ast.TokenIndex = 0;
    while (t < tree.tokens.len) : (t += 1) {
        if (p.inTest(t)) continue;
        if (tree.tokenTag(t) == .keyword_return) {
            try list.append(gpa, try deleteReturn(gpa, p, t));
            continue;
        }
        const text = tree.tokenSlice(t);
        const swap = swapFor(tree.tokenTag(t), text) orelse continue;
        const start = tree.tokenStart(t);
        try list.append(gpa, .{
            .start = start,
            .end = start + @as(u32, @intCast(text.len)),
            .replacement = swap,
            .line = p.line(t),
            .column = p.column(t),
            .description = try std.fmt.allocPrint(gpa, "`{s}` → `{s}`", .{ text, swap }),
        });
    }
    return list.toOwnedSlice(gpa);
}

/// Troca `return ...;` por `{}`, um comando vazio.
fn deleteReturn(gpa: std.mem.Allocator, p: Parsed, ret: Ast.TokenIndex) !Mutant {
    const tree = p.tree;
    var depth: u32 = 0;
    var t = ret + 1;
    while (t < tree.tokens.len) : (t += 1) {
        switch (tree.tokenTag(t)) {
            .l_paren, .l_brace, .l_bracket => depth += 1,
            .r_paren, .r_brace, .r_bracket => depth -|= 1,
            .semicolon => if (depth == 0) break,
            else => {},
        }
    }
    return .{
        .start = tree.tokenStart(ret),
        .end = tree.tokenStart(t) + 1,
        .replacement = "{}",
        .line = p.line(ret),
        .column = p.column(ret),
        .description = try gpa.dupe(u8, "apaga o `return`"),
    };
}

/// Texto que substitui o token, se ele tiver mutação.
fn swapFor(tag: std.zig.Token.Tag, text: []const u8) ?[]const u8 {
    return switch (tag) {
        .angle_bracket_left => "<=",
        .angle_bracket_left_equal => "<",
        .angle_bracket_right => ">=",
        .angle_bracket_right_equal => ">",
        .equal_equal => "!=",
        .bang_equal => "==",
        .plus => "-",
        .minus => "+",
        .plus_equal => "-=",
        .minus_equal => "+=",
        .plus_pipe => "-|",
        .minus_pipe => "+|",
        .plus_pipe_equal => "-|=",
        .minus_pipe_equal => "+|=",
        .identifier => if (std.mem.eql(u8, text, "true"))
            "false"
        else if (std.mem.eql(u8, text, "false"))
            "true"
        else
            null,
        else => null,
    };
}

/// Aplica o mutante ao código. Memória do chamador.
pub fn apply(gpa: std.mem.Allocator, code: []const u8, m: Mutant) ![:0]u8 {
    return std.mem.concatWithSentinel(gpa, u8, &.{ code[0..m.start], m.replacement, code[m.end..] }, 0);
}

fn expectMutations(code: [:0]const u8, expected: []const []const u8) !void {
    const gpa = std.testing.allocator;
    var p: Parsed = try .init(gpa, code);
    defer p.deinit(gpa);
    const found = try mutants(gpa, p);
    defer {
        for (found) |m| gpa.free(m.description);
        gpa.free(found);
    }
    try std.testing.expectEqual(expected.len, found.len);
    for (found, expected) |m, want| {
        const got = try apply(gpa, code, m);
        defer gpa.free(got);
        try std.testing.expectEqualStrings(want, got);
    }
}

test "mutants: troca comparação, soma e booleano" {
    try expectMutations("const a = x < y;", &.{"const a = x <= y;"});
    try expectMutations("const a = x >= y;", &.{"const a = x > y;"});
    try expectMutations("const a = x == y;", &.{"const a = x != y;"});
    try expectMutations("const a = x + y;", &.{"const a = x - y;"});
    try expectMutations("const a = true;", &.{"const a = false;"});
}

test "mutants: guarda linha e coluna, para separar mutantes da mesma linha" {
    const gpa = std.testing.allocator;
    var p: Parsed = try .init(gpa, "const a = x < 0 and\n    y < 0;");
    defer p.deinit(gpa);
    const found = try mutants(gpa, p);
    defer {
        for (found) |m| gpa.free(m.description);
        gpa.free(found);
    }
    try std.testing.expectEqual(2, found.len);
    try std.testing.expectEqual(1, found[0].line);
    try std.testing.expectEqual(13, found[0].column);
    try std.testing.expectEqual(2, found[1].line);
    try std.testing.expectEqual(7, found[1].column);
}

test "mutants: apaga o return inteiro, até o ponto e vírgula" {
    try expectMutations("fn f() void { if (c) return; g(); }", &.{"fn f() void { if (c) {} g(); }"});
    try expectMutations("fn f() u8 { return h(a, b); }", &.{"fn f() u8 { {} }"});
}

test "mutants: não muta código de blocos test" {
    try expectMutations("test \"t\" { _ = 1 + 2; }", &.{});
}

/// Comentário que desliga a mutação na linha dele e na de baixo.
const directive_marker = "// mutation: disable";
const Directive = source.Directive;

fn directives(gpa: std.mem.Allocator, code: []const u8) ![]Directive {
    return source.directives(gpa, code, directive_marker);
}

const isDisabled = source.isCovered;

pub const Outcome = enum { killed, survived, no_compile, timeout };

/// Código de saída do `timeout` (coreutils) quando o tempo acaba.
const timeout_exit_code = 124;

/// Resultado de `zig test` sobre um mutante.
pub fn classify(term: std.process.Child.Term, stderr: []const u8) Outcome {
    switch (term) {
        .exited => |code| {
            if (code == 0) return .survived;
            if (code == timeout_exit_code) return .timeout;
        },
        else => {},
    }
    return if (hasCompileError(stderr)) .no_compile else .killed;
}

/// Erro de compilação tem a forma `arquivo.zig:linha:coluna: error:`.
fn hasCompileError(stderr: []const u8) bool {
    var lines = std.mem.splitScalar(u8, stderr, '\n');
    while (lines.next()) |line| {
        const zig_at = std.mem.indexOf(u8, line, ".zig:") orelse continue;
        var parts = std.mem.splitScalar(u8, line[zig_at + ".zig:".len ..], ':');
        const row = parts.next() orelse continue;
        const col = parts.next() orelse continue;
        const rest = parts.rest();
        if (isNumber(row) and isNumber(col) and std.mem.startsWith(u8, rest, " error")) return true;
    }
    return false;
}

fn isNumber(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| {
        if (!std.ascii.isDigit(c)) return false;
    }
    return true;
}

test "classify: separa sobrevivente, morto, não compilou e tempo esgotado" {
    try std.testing.expectEqual(.survived, classify(.{ .exited = 0 }, ""));
    try std.testing.expectEqual(.killed, classify(.{ .exited = 1 }, "error: 'health.test.x' failed:\n"));
    try std.testing.expectEqual(.no_compile, classify(.{ .exited = 1 }, "src/health.zig:18:22: error: expected type\n"));
    try std.testing.expectEqual(.timeout, classify(.{ .exited = timeout_exit_code }, ""));
}
