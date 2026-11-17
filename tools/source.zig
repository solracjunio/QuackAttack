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

    /// Coluna do token, começando em 1.
    pub fn column(self: Parsed, token: Ast.TokenIndex) u32 {
        return @intCast(self.tree.tokenLocation(0, token).column + 1);
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
    return readFiles(arena, io, dir_path, ".zig");
}

/// Lê os arquivos de `dir_path` que terminam em `suffix` (todos, se null),
/// recursivamente, em ordem de caminho.
pub fn readFiles(arena: std.mem.Allocator, io: std.Io, dir_path: []const u8, suffix: ?[]const u8) ![]SourceFile {
    var dir = try std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true });
    defer dir.close(io);
    return readFilesIn(arena, io, dir, suffix);
}

/// Como `readFiles`, num diretório já aberto (com `.iterate = true`).
pub fn readFilesIn(arena: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, suffix: ?[]const u8) ![]SourceFile {
    var walker = try dir.walk(arena);
    defer walker.deinit();

    var files: std.ArrayList(SourceFile) = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (suffix) |wanted| {
            if (!std.mem.endsWith(u8, entry.path, wanted)) continue;
        }
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

/// Comentário de exceção (`// mutation: disable — <motivo>`,
/// `// magic: allow — <motivo>`) numa linha do código.
pub const Directive = struct { line: u32, has_reason: bool };

/// Comentários com `marker`, com a linha (a partir de 1) de cada um.
pub fn directives(gpa: std.mem.Allocator, code: []const u8, marker: []const u8) ![]Directive {
    var list: std.ArrayList(Directive) = .empty;
    errdefer list.deinit(gpa);
    var lines = std.mem.splitScalar(u8, code, '\n');
    var n: u32 = 1;
    while (lines.next()) |text| : (n += 1) {
        const at = std.mem.indexOf(u8, text, marker) orelse continue;
        const rest = std.mem.trim(u8, text[at + marker.len ..], " \t\r—-");
        try list.append(gpa, .{ .line = n, .has_reason = rest.len > 0 });
    }
    return list.toOwnedSlice(gpa);
}

/// O comentário vale para a própria linha e para a linha de baixo, e só com motivo.
pub fn isCovered(ds: []const Directive, line: u32) bool {
    for (ds) |d| {
        if (d.has_reason and (line == d.line or line == d.line + 1)) return true;
    }
    return false;
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

test "column: começa em 1" {
    var p: Parsed = try .init(std.testing.allocator, sample);
    defer p.deinit(std.testing.allocator);
    try std.testing.expectEqual(12, p.column(findToken(p.tree, "7")));
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

test "directives: acha o comentário e diz se tem motivo" {
    const gpa = std.testing.allocator;
    const code =
        \\const a = x + y; // mutation: disable — overflow impossível aqui
        \\// mutation: disable
        \\const b = x - y;
    ;
    const ds = try directives(gpa, code, "// mutation: disable");
    defer gpa.free(ds);
    try std.testing.expectEqual(2, ds.len);
    try std.testing.expectEqual(Directive{ .line = 1, .has_reason = true }, ds[0]);
    try std.testing.expectEqual(Directive{ .line = 2, .has_reason = false }, ds[1]);
}

test "isCovered: vale na linha e na de baixo, só com motivo" {
    const ds = [_]Directive{ .{ .line = 1, .has_reason = true }, .{ .line = 5, .has_reason = false } };
    try std.testing.expect(isCovered(&ds, 1));
    try std.testing.expect(isCovered(&ds, 2));
    try std.testing.expect(!isCovered(&ds, 3));
    try std.testing.expect(!isCovered(&ds, 6));
}

test "readFilesIn: sem filtro lê todos os arquivos (inclusive .zon), em ordem; com filtro, só os do sufixo" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try tmp.dir.createDirPath(io, "sub");
    try tmp.dir.writeFile(io, .{ .sub_path = "b.zig", .data = "const b = 1;" });
    try tmp.dir.writeFile(io, .{ .sub_path = "sub/a.zon", .data = ".{}" });

    const all = try readFilesIn(arena.allocator(), io, tmp.dir, null);
    try std.testing.expectEqual(2, all.len);
    try std.testing.expectEqualStrings("b.zig", all[0].path);
    try std.testing.expectEqualStrings("sub/a.zon", all[1].path);
    try std.testing.expectEqualStrings(".{}", all[1].source);

    const zig_only = try readFilesIn(arena.allocator(), io, tmp.dir, ".zig");
    try std.testing.expectEqual(1, zig_only.len);
}
