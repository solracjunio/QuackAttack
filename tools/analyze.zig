//! Análise estática de `src/`: imports entre sistemas e ciclos,
//! números mágicos e complexidade por função.
const std = @import("std");
const Ast = std.zig.Ast;
const source = @import("source.zig");
const Parsed = source.Parsed;

/// Uso: analyze <pasta src> <saída .zon>
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 3) return error.Usage;
    const files = try source.readZigFiles(arena, init.io, args[1]);
    const report = try analyzeFiles(arena, files);
    try source.writeZon(arena, init.io, args[2], report);
}

/// Caminhos passados a `@import("...")`, na ordem em que aparecem.
/// As fatias apontam para o código-fonte do `Parsed`.
pub fn imports(gpa: std.mem.Allocator, p: Parsed) ![][]const u8 {
    const tree = p.tree;
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(gpa);
    var t: Ast.TokenIndex = 0;
    while (t + 2 < tree.tokens.len) : (t += 1) {
        if (tree.tokenTag(t) != .builtin) continue;
        if (!std.mem.eql(u8, tree.tokenSlice(t), "@import")) continue;
        if (tree.tokenTag(t + 2) != .string_literal) continue;
        const quoted = tree.tokenSlice(t + 2);
        try list.append(gpa, quoted[1 .. quoted.len - 1]);
    }
    return list.toOwnedSlice(gpa);
}

test "imports: lista os caminhos de @import, sem as aspas" {
    const gpa = std.testing.allocator;
    var p: Parsed = try .init(gpa,
        \\const std = @import("std");
        \\const health = @import("health.zig");
    );
    defer p.deinit(gpa);
    const found = try imports(gpa, p);
    defer gpa.free(found);
    try std.testing.expectEqual(2, found.len);
    try std.testing.expectEqualStrings("std", found[0]);
    try std.testing.expectEqualStrings("health.zig", found[1]);
}

/// Caminho, relativo a `src/`, do arquivo que `from` importa com `import`.
/// Devolve null para módulos que não são arquivo (`std`, `raylib`...).
pub fn resolveImport(arena: std.mem.Allocator, from: []const u8, import: []const u8) !?[]const u8 {
    if (!std.mem.endsWith(u8, import, ".zig")) return null;
    const dir = std.fs.path.dirnamePosix(from) orelse ".";
    return try std.fs.path.resolveAllocPosix(arena, &.{ dir, import });
}

test "resolveImport: resolve relativo à pasta de quem importa" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("systems/seguir.zig", (try resolveImport(a, "systems/mover.zig", "seguir.zig")).?);
    try std.testing.expectEqualStrings("events.zig", (try resolveImport(a, "systems/mover.zig", "../events.zig")).?);
    try std.testing.expectEqualStrings("health.zig", (try resolveImport(a, "game.zig", "health.zig")).?);
}

test "resolveImport: ignora módulos que não são arquivo" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqual(null, try resolveImport(arena.allocator(), "main.zig", "raylib"));
}

/// Imports de um arquivo, com o caminho dele relativo a `src/`.
pub const FileImports = struct {
    path: []const u8,
    imports: []const []const u8,
};

pub const Edge = struct { from: []const u8, to: []const u8 };

const systems_dir = "systems/";

/// Imports em que um sistema importa outro sistema.
pub fn systemViolations(arena: std.mem.Allocator, files: []const FileImports) ![]Edge {
    var list: std.ArrayList(Edge) = .empty;
    for (files) |f| {
        if (!std.mem.startsWith(u8, f.path, systems_dir)) continue;
        for (f.imports) |imp| {
            const to = try resolveImport(arena, f.path, imp) orelse continue;
            if (std.mem.startsWith(u8, to, systems_dir)) try list.append(arena, .{ .from = f.path, .to = to });
        }
    }
    return list.toOwnedSlice(arena);
}

test "systemViolations: acusa sistema importando sistema, aceita sistema importando events" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const files = [_]FileImports{
        .{ .path = "systems/mover.zig", .imports = &.{ "std", "../events.zig", "seguir.zig" } },
        .{ .path = "systems/seguir.zig", .imports = &.{"../events.zig"} },
        .{ .path = "main.zig", .imports = &.{"systems/mover.zig"} },
    };
    const found = try systemViolations(arena.allocator(), &files);
    try std.testing.expectEqual(1, found.len);
    try std.testing.expectEqualStrings("systems/mover.zig", found[0].from);
    try std.testing.expectEqualStrings("systems/seguir.zig", found[0].to);
}

/// Um ciclo de imports entre arquivos de `src/`, se houver:
/// a lista começa e termina no mesmo arquivo (`a -> b -> a`).
pub fn findCycle(arena: std.mem.Allocator, files: []const FileImports) !?[]const []const u8 {
    var dfs: CycleSearch = .{
        .arena = arena,
        .files = files,
        .state = try arena.alloc(CycleSearch.Visit, files.len),
    };
    @memset(dfs.state, .new);
    for (files, 0..) |f, i| try dfs.index.put(arena, f.path, i);
    for (0..files.len) |i| {
        if (try dfs.visit(i)) |cycle| return cycle;
    }
    return null;
}

/// Busca em profundidade: um arquivo ainda `active` reencontrado fecha um ciclo.
const CycleSearch = struct {
    const Visit = enum { new, active, done };

    arena: std.mem.Allocator,
    files: []const FileImports,
    state: []Visit,
    index: std.StringHashMapUnmanaged(usize) = .empty,
    stack: std.ArrayList([]const u8) = .empty,

    fn visit(self: *CycleSearch, i: usize) !?[]const []const u8 {
        const path = self.files[i].path;
        switch (self.state[i]) {
            .done => return null,
            .active => return try self.cycleEndingAt(path),
            .new => {},
        }
        self.state[i] = .active;
        try self.stack.append(self.arena, path);
        for (self.files[i].imports) |imp| {
            const to = try resolveImport(self.arena, path, imp) orelse continue;
            const next = self.index.get(to) orelse continue;
            if (try self.visit(next)) |cycle| return cycle;
        }
        _ = self.stack.pop();
        self.state[i] = .done;
        return null;
    }

    fn cycleEndingAt(self: *CycleSearch, path: []const u8) ![]const []const u8 {
        var start: usize = 0;
        for (self.stack.items, 0..) |p, k| {
            if (std.mem.eql(u8, p, path)) start = k;
        }
        var cycle: std.ArrayList([]const u8) = .empty;
        try cycle.appendSlice(self.arena, self.stack.items[start..]);
        try cycle.append(self.arena, path);
        return cycle.toOwnedSlice(self.arena);
    }
};

test "findCycle: acha a -> b -> c -> a" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const files = [_]FileImports{
        .{ .path = "a.zig", .imports = &.{ "std", "b.zig" } },
        .{ .path = "b.zig", .imports = &.{"c.zig"} },
        .{ .path = "c.zig", .imports = &.{"a.zig"} },
    };
    const cycle = (try findCycle(arena.allocator(), &files)) orelse return error.TestExpectedCycle;
    try std.testing.expectEqual(4, cycle.len);
    try std.testing.expectEqualStrings(cycle[0], cycle[3]);
}

test "findCycle: null quando dois arquivos importam o mesmo (diamante não é ciclo)" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const files = [_]FileImports{
        .{ .path = "a.zig", .imports = &.{ "b.zig", "c.zig" } },
        .{ .path = "b.zig", .imports = &.{"d.zig"} },
        .{ .path = "c.zig", .imports = &.{"d.zig"} },
        .{ .path = "d.zig", .imports = &.{} },
    };
    try std.testing.expectEqual(null, try findCycle(arena.allocator(), &files));
}

pub const Magic = struct { line: u32, text: []const u8 };

/// Literais numéricos fora de blocos `test`, exceto 0 e 1.
pub fn magicNumbers(gpa: std.mem.Allocator, p: Parsed) ![]Magic {
    const allowed = [_][]const u8{ "0", "1", "0.0", "1.0" };
    var list: std.ArrayList(Magic) = .empty;
    errdefer list.deinit(gpa);
    var t: Ast.TokenIndex = 0;
    next: while (t < p.tree.tokens.len) : (t += 1) {
        if (p.tree.tokenTag(t) != .number_literal or p.inTest(t)) continue;
        const text = p.tree.tokenSlice(t);
        for (allowed) |a| {
            if (std.mem.eql(u8, text, a)) continue :next;
        }
        try list.append(gpa, .{ .line = p.line(t), .text = text });
    }
    return list.toOwnedSlice(gpa);
}

test "magicNumbers: acusa literais fora de 0 e 1, ignora os de teste" {
    const gpa = std.testing.allocator;
    var p: Parsed = try .init(gpa,
        \\const speed = 120;
        \\fn f(x: i32) i32 {
        \\    if (x > 0) return x - 1;
        \\    return -1 + 2.5;
        \\}
        \\test "f" {
        \\    _ = f(99);
        \\}
    );
    defer p.deinit(gpa);
    const found = try magicNumbers(gpa, p);
    defer gpa.free(found);
    try std.testing.expectEqual(2, found.len);
    try std.testing.expectEqualStrings("120", found[0].text);
    try std.testing.expectEqual(1, found[0].line);
    try std.testing.expectEqualStrings("2.5", found[1].text);
    try std.testing.expectEqual(4, found[1].line);
}

pub const FnComplexity = struct { name: []const u8, line: u32, score: u32 };

/// Complexidade de cada função fora de blocos `test`: 1 + cada `if`, `while`,
/// `for`, `and`, `or`, `catch`, `orelse` e ramo de `switch`.
pub fn complexity(gpa: std.mem.Allocator, p: Parsed) ![]FnComplexity {
    const tree = p.tree;
    var list: std.ArrayList(FnComplexity) = .empty;
    errdefer list.deinit(gpa);
    for (0..tree.nodes.len) |i| {
        const node: Ast.Node.Index = @fromBackingInt(@intCast(i));
        if (tree.nodeTag(node) != .fn_decl) continue;
        const first = tree.firstToken(node);
        if (p.inTest(first)) continue;
        var buf: [1]Ast.Node.Index = undefined;
        const name_token = tree.fullFnProto(&buf, node).?.name_token orelse continue;
        try list.append(gpa, .{
            .name = tree.tokenSlice(name_token),
            .line = p.line(name_token),
            .score = 1 + countBranches(tree, first, tree.lastToken(node)),
        });
    }
    std.mem.sort(FnComplexity, list.items, {}, byLine);
    return list.toOwnedSlice(gpa);
}

fn countBranches(tree: Ast, first: Ast.TokenIndex, last: Ast.TokenIndex) u32 {
    var n: u32 = 0;
    for (first..last + 1) |t| {
        switch (tree.tokenTag(@intCast(t))) {
            .keyword_if,
            .keyword_while,
            .keyword_for,
            .keyword_and,
            .keyword_or,
            .keyword_catch,
            .keyword_orelse,
            .equal_angle_bracket_right,
            => n += 1,
            else => {},
        }
    }
    return n;
}

fn byLine(_: void, a: FnComplexity, b: FnComplexity) bool {
    return a.line < b.line;
}

test "complexity: conta 1 mais cada desvio, por função" {
    const gpa = std.testing.allocator;
    var p: Parsed = try .init(gpa,
        \\fn simples() void {}
        \\fn desvios(x: ?u32, y: bool) u32 {
        \\    if (y and x != null) return 0;
        \\    for (0..3) |_| {}
        \\    const v = x orelse 0;
        \\    return switch (v) {
        \\        0 => 1,
        \\        else => 2,
        \\    };
        \\}
    );
    defer p.deinit(gpa);
    const found = try complexity(gpa, p);
    defer gpa.free(found);
    try std.testing.expectEqual(2, found.len);
    try std.testing.expectEqualStrings("simples", found[0].name);
    try std.testing.expectEqual(1, found[0].score);
    try std.testing.expectEqualStrings("desvios", found[1].name);
    try std.testing.expectEqual(2, found[1].line);
    // 1 + if + and + for + orelse + 2 ramos de switch
    try std.testing.expectEqual(7, found[1].score);
}

pub const SourceFile = source.SourceFile;

pub const Report = struct {
    pub const FileMagic = struct { path: []const u8, line: u32, text: []const u8 };
    pub const FileFn = struct { path: []const u8, name: []const u8, line: u32, score: u32 };

    system_violations: []const Edge = &.{},
    cycle: ?[]const []const u8 = null,
    magic: []const FileMagic = &.{},
    functions: []const FileFn = &.{},
};

/// Junta todas as análises. Tudo é alocado no `arena`.
pub fn analyzeFiles(arena: std.mem.Allocator, files: []const SourceFile) !Report {
    var graph: std.ArrayList(FileImports) = .empty;
    var magic: std.ArrayList(Report.FileMagic) = .empty;
    var functions: std.ArrayList(Report.FileFn) = .empty;

    for (files) |f| {
        // Sem deinit: o Parsed vive no arena, e os textos do relatório apontam para o código.
        const p: Parsed = try .init(arena, f.source);
        try graph.append(arena, .{ .path = f.path, .imports = try imports(arena, p) });
        if (!source.isScreenCode(f.path)) {
            for (try magicNumbers(arena, p)) |m| {
                try magic.append(arena, .{ .path = f.path, .line = m.line, .text = m.text });
            }
        }
        for (try complexity(arena, p)) |c| {
            try functions.append(arena, .{ .path = f.path, .name = c.name, .line = c.line, .score = c.score });
        }
    }

    return .{
        .system_violations = try systemViolations(arena, graph.items),
        .cycle = try findCycle(arena, graph.items),
        .magic = magic.items,
        .functions = functions.items,
    };
}

test "analyzeFiles: ignora números de tela em main.zig e ui/, mas mede a complexidade deles" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const files = [_]SourceFile{
        .{ .path = "main.zig", .source = "const width = 960;\nfn main() void {}" },
        .{ .path = "ui/hud.zig", .source = "const font = 32;" },
        .{ .path = "world.zig", .source = "const speed = 120;\nfn tick(x: bool) void { if (x) {} }" },
    };
    const r = try analyzeFiles(arena.allocator(), &files);
    try std.testing.expectEqual(1, r.magic.len);
    try std.testing.expectEqualStrings("world.zig", r.magic[0].path);
    try std.testing.expectEqualStrings("120", r.magic[0].text);
    try std.testing.expectEqual(2, r.functions.len);
    try std.testing.expectEqualStrings("main", r.functions[0].name);
    try std.testing.expectEqual(2, r.functions[1].score);
    try std.testing.expectEqual(null, r.cycle);
}
