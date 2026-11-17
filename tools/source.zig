//! Leitura de código Zig pela AST, comum às ferramentas de qualidade.
const std = @import("std");
const Ast = std.zig.Ast;

pub const TokenRange = struct { first: Ast.TokenIndex, last: Ast.TokenIndex };

/// Um arquivo `.zig` já analisado.
pub const Parsed = struct {
    tree: Ast,
    test_ranges: []TokenRange,

    pub fn init(gpa: std.mem.Allocator, source: [:0]const u8) !Parsed {
        var tree = try Ast.parse(gpa, source, .{});
        errdefer tree.deinit(gpa);

        var ranges: std.ArrayList(TokenRange) = .empty;
        errdefer ranges.deinit(gpa);
        for (0..tree.nodes.len) |i| {
            const node: Ast.Node.Index = @fromBackingInt(@intCast(i));
            if (tree.nodeTag(node) != .test_decl) continue;
            try ranges.append(gpa, .{ .first = tree.firstToken(node), .last = tree.lastToken(node) });
        }
        return .{ .tree = tree, .test_ranges = try ranges.toOwnedSlice(gpa) };
    }

    pub fn deinit(self: *Parsed, gpa: std.mem.Allocator) void {
        gpa.free(self.test_ranges);
        self.tree.deinit(gpa);
    }

    /// Verdadeiro se o token está dentro de um bloco `test`.
    pub fn inTest(self: Parsed, token: Ast.TokenIndex) bool {
        for (self.test_ranges) |r| {
            if (token >= r.first and token <= r.last) return true;
        }
        return false;
    }

    /// Linha do token, começando em 1.
    pub fn line(self: Parsed, token: Ast.TokenIndex) u32 {
        return @intCast(self.tree.tokenLocation(0, token).line + 1);
    }
};

/// Um arquivo `.zig`, com o caminho relativo à pasta lida (separador `/`).
pub const SourceFile = struct { path: []const u8, source: [:0]const u8 };

/// Arquivos de tela (`main.zig` e `ui/`): números como o tamanho da janela são
/// permitidos, e eles ficam fora da mutação e da cobertura.
pub fn isScreenCode(path: []const u8) bool {
    return std.mem.eql(u8, path, "main.zig") or std.mem.startsWith(u8, path, "ui/");
}

/// Lê todos os `.zig` de `dir_path`, recursivamente, em ordem de caminho.
pub fn readZigFiles(arena: std.mem.Allocator, io: std.Io, dir_path: []const u8) ![]SourceFile {
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(arena);
    defer walker.deinit();

    var files: std.ArrayList(SourceFile) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.path, ".zig")) continue;
        const text = try dir.readFileAllocOptions(io, entry.path, arena, .unlimited, .of(u8), 0);
        try files.append(arena, .{ .path = try arena.dupe(u8, entry.path), .source = text });
    }
    std.mem.sort(SourceFile, files.items, {}, byPath);
    return files.items;
}

fn byPath(_: void, a: SourceFile, b: SourceFile) bool {
    return std.mem.lessThan(u8, a.path, b.path);
}

/// Grava `value` em ZON no arquivo `path`.
pub fn writeZon(gpa: std.mem.Allocator, io: std.Io, path: []const u8, value: anytype) !void {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    try std.zon.stringify.serialize(value, .{}, &out.writer);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = out.written() });
}

/// Primeiro token com este texto (para os testes acharem tokens).
fn findToken(tree: Ast, text: []const u8) Ast.TokenIndex {
    var i: Ast.TokenIndex = 0;
    while (i < tree.tokens.len) : (i += 1) {
        if (std.mem.eql(u8, tree.tokenSlice(i), text)) return i;
    }
    unreachable;
}

const sample =
    \\fn f() u32 {
    \\    return 7;
    \\}
    \\test "f" {
    \\    _ = 42;
    \\}
;

test "inTest: verdadeiro para token de bloco test, falso fora dele" {
    var p: Parsed = try .init(std.testing.allocator, sample);
    defer p.deinit(std.testing.allocator);
    try std.testing.expect(!p.inTest(findToken(p.tree, "7")));
    try std.testing.expect(p.inTest(findToken(p.tree, "42")));
}

test "line: começa em 1" {
    var p: Parsed = try .init(std.testing.allocator, sample);
    defer p.deinit(std.testing.allocator);
    try std.testing.expectEqual(2, p.line(findToken(p.tree, "7")));
}

test "inTest: o primeiro e o último token do bloco test contam como dentro" {
    var p: Parsed = try .init(std.testing.allocator, sample);
    defer p.deinit(std.testing.allocator);
    const last: Ast.TokenIndex = @intCast(p.tree.tokens.len - 2); // o último é o fim de arquivo
    try std.testing.expect(p.inTest(findToken(p.tree, "test")));
    try std.testing.expect(p.inTest(last));
}
