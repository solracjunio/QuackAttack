//! Junta os resultados de `analyze`, kcov, `mutate` e `git log`, gera as
//! tabelas com semáforo e decide se o `zig build quality` reprova.
const std = @import("std");
const source = @import("source.zig");
const SourceFile = source.SourceFile;
const Parsed = source.Parsed;
const analyze = @import("analyze.zig");
const mutate = @import("mutate.zig");

/// Tudo o que o relatório lê.
pub const Inputs = struct {
    analysis: analyze.Report,
    mutation: mutate.Report,
    coverage: []const FileCoverage,
    fixes: FixStats,
};

/// Uso: report <analyze.zon> <cobertura.xml> <mutate.zon> <git log> <pasta src> <medicoes.md>
///
/// Imprime o relatório, grava no Job Summary (se `GITHUB_STEP_SUMMARY` existir)
/// e no bloco gerado do `medicoes.md`. Sai com 1 se alguma regra reprovar.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const io = init.io;
    const cwd = std.Io.Dir.cwd();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len != 7) return error.Usage;

    const files = try source.readZigFiles(arena, io, args[5]);
    const in: Inputs = .{
        .analysis = try readZon(analyze.Report, arena, io, args[1]),
        .coverage = try coverage(arena, try cwd.readFileAlloc(io, args[2], arena, .unlimited), files),
        .mutation = try readZon(mutate.Report, arena, io, args[3]),
        .fixes = fixCommits(try cwd.readFileAlloc(io, args[4], arena, .unlimited)),
    };
    const md = try render(arena, in);

    // Uma escrita só: com buffer, a saída do `zig build` se mistura no meio do relatório.
    try std.Io.File.stdout().writeStreamingAll(io, md);

    if (init.environ_map.get("GITHUB_STEP_SUMMARY")) |summary| try appendFile(arena, io, summary, md);

    const doc = cwd.readFileAlloc(io, args[6], arena, .unlimited) catch |err| switch (err) {
        error.FileNotFound => "",
        else => return err,
    };
    try cwd.writeFile(io, .{ .sub_path = args[6], .data = try replaceBlock(arena, doc, md) });

    if ((try failures(arena, in)).len > 0) std.process.exit(1);
}

fn readZon(T: type, arena: std.mem.Allocator, io: std.Io, path: []const u8) !T {
    const text = try std.Io.Dir.cwd().readFileAllocOptions(io, path, arena, .unlimited, .of(u8), 0);
    var diag: std.zon.parse.Diagnostics = undefined;
    return std.zon.parse.fromSlice(T, .{ .gpa = arena, .arena = arena, .source = text, .diagnostics = &diag }) catch |err| {
        diag.log(path);
        return err;
    };
}

fn appendFile(arena: std.mem.Allocator, io: std.Io, path: []const u8, data: []const u8) !void {
    const cwd = std.Io.Dir.cwd();
    const old = cwd.readFileAlloc(io, path, arena, .unlimited) catch "";
    try cwd.writeFile(io, .{ .sub_path = path, .data = try std.mem.concat(arena, u8, &.{ old, data }) });
}

pub const FileCoverage = struct { path: []const u8, covered: u32, total: u32 };

/// Linhas cobertas por arquivo, a partir do `cobertura.xml` do kcov.
/// Descontam-se as linhas de blocos `test` e os arquivos de tela.
pub fn coverage(arena: std.mem.Allocator, cobertura: []const u8, files: []const SourceFile) ![]FileCoverage {
    var result: std.ArrayList(FileCoverage) = .empty;
    var classes = std.mem.splitSequence(u8, cobertura, "<class ");
    _ = classes.next(); // antes da primeira classe
    while (classes.next()) |class| {
        const path = attr(class, "filename") orelse continue;
        if (source.isScreenCode(path)) continue;
        const file = findFile(files, path) orelse continue;
        const p: Parsed = try .init(arena, file.source);

        var fc: FileCoverage = .{ .path = path, .covered = 0, .total = 0 };
        const body = class[0 .. std.mem.indexOf(u8, class, "</class>") orelse class.len];
        var lines = std.mem.splitSequence(u8, body, "<line ");
        _ = lines.next();
        while (lines.next()) |line| {
            const number = try std.fmt.parseInt(u32, attr(line, "number") orelse continue, 10);
            const hits = try std.fmt.parseInt(u64, attr(line, "hits") orelse continue, 10);
            if (isTestLine(p, number)) continue;
            fc.total += 1;
            if (hits > 0) fc.covered += 1;
        }
        try result.append(arena, fc);
    }
    return result.items;
}

/// Valor de `name="..."` no trecho de XML (no início do trecho ou depois de espaço).
fn attr(xml: []const u8, comptime name: []const u8) ?[]const u8 {
    const key = name ++ "=\"";
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, xml, from, key)) |at| : (from = at + 1) {
        if (at != 0 and xml[at - 1] != ' ') continue;
        const start = at + key.len;
        const end = std.mem.indexOfScalarPos(u8, xml, start, '"') orelse return null;
        return xml[start..end];
    }
    return null;
}

fn findFile(files: []const SourceFile, path: []const u8) ?SourceFile {
    for (files) |f| {
        if (std.mem.eql(u8, f.path, path)) return f;
    }
    return null;
}

fn isTestLine(p: Parsed, line: u32) bool {
    for (p.test_ranges) |r| {
        if (line >= p.line(r.first) and line <= p.line(r.last)) return true;
    }
    return false;
}

test "coverage: conta linhas por arquivo, sem linhas de test nem código de tela" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const files = [_]SourceFile{
        .{ .path = "health.zig", .source = "fn a() void {\n    b();\n}\nfn c() void {}\ntest \"a\" {\n    a();\n}" },
        .{ .path = "main.zig", .source = "pub fn main() void {}" },
    };
    const xml =
        \\<classes>
        \\<class name="health_zig__0" filename="health.zig" line-rate="0.6">
        \\<lines>
        \\<line number="1" hits="1"/>
        \\<line number="2" hits="1"/>
        \\<line number="4" hits="0"/>
        \\<line number="6" hits="1"/>
        \\</lines>
        \\</class>
        \\<class name="main_zig__1" filename="main.zig" line-rate="0.0">
        \\<lines>
        \\<line number="1" hits="0"/>
        \\</lines>
        \\</class>
        \\</classes>
    ;
    const found = try coverage(arena.allocator(), xml, &files);
    try std.testing.expectEqual(1, found.len);
    try std.testing.expectEqualStrings("health.zig", found[0].path);
    try std.testing.expectEqual(2, found[0].covered);
    try std.testing.expectEqual(3, found[0].total);
}

pub const FixStats = struct { fixes: u32 = 0, with_tests: u32 = 0 };

/// Separador de commits no `git log --format=%x1e%s -p` que o build gera.
pub const commit_separator = "\x1e";

/// Quantos commits `fix:` existem e quantos adicionam um `test "..."`.
pub fn fixCommits(log: []const u8) FixStats {
    var stats: FixStats = .{};
    var commits = std.mem.splitSequence(u8, log, commit_separator);
    while (commits.next()) |commit| {
        var lines = std.mem.splitScalar(u8, commit, '\n');
        if (!isFixSubject(lines.first())) continue;
        stats.fixes += 1;
        while (lines.next()) |line| {
            if (line.len == 0 or line[0] != '+' or std.mem.startsWith(u8, line, "+++")) continue;
            if (std.mem.startsWith(u8, std.mem.trimStart(u8, line[1..], " \t"), "test \"")) {
                stats.with_tests += 1;
                break;
            }
        }
    }
    return stats;
}

/// `fix: ...`, `fix(escopo): ...` ou `fix!: ...` (Conventional Commits).
fn isFixSubject(subject: []const u8) bool {
    if (!std.mem.startsWith(u8, subject, "fix")) return false;
    const rest = subject["fix".len..];
    return std.mem.startsWith(u8, rest, ":") or std.mem.startsWith(u8, rest, "(") or std.mem.startsWith(u8, rest, "!:");
}

test "fixCommits: conta fix com e sem teste novo, ignora outros tipos" {
    const log = commit_separator ++ "fix(health): cura passava do máximo\n" ++
        "+++ b/src/health.zig\n" ++
        "+test \"heal: para no máximo\" {\n" ++
        commit_separator ++ "fix: corrige texto\n" ++
        "+    const a = 1;\n" ++
        commit_separator ++ "feat: adiciona mago\n" ++
        "+test \"mago\" {\n" ++
        commit_separator ++ "fixture: não é fix\n";
    const s = fixCommits(log);
    try std.testing.expectEqual(2, s.fixes);
    try std.testing.expectEqual(1, s.with_tests);
}

pub const Light = enum {
    green,
    yellow,
    red,

    pub fn emoji(self: Light) []const u8 {
        return switch (self) {
            .green => "🟢",
            .yellow => "🟡",
            .red => "🔴",
        };
    }
};

/// Cobertura: 🟢 ≥ 90% · 🟡 80–90% · 🔴 < 80%.
pub fn coverageLight(pct: f64) Light {
    if (pct >= 90.0) return .green;
    return if (pct >= 80.0) .yellow else .red;
}

/// Complexidade por função: 🟢 até 10 · 🟡 11–15 · 🔴 acima de 15.
pub fn complexityLight(score: u32) Light {
    if (score <= 10) return .green;
    return if (score <= 15) .yellow else .red;
}

/// Números mágicos: 🟢 0 · 🟡 1–5 · 🔴 > 5.
pub fn magicLight(count: usize) Light {
    if (count == 0) return .green;
    return if (count <= 5) .yellow else .red;
}

/// Commits `fix:` com teste: 🟢 100% · 🟡 ≥ 80% · 🔴 < 80%. Sem fix, verde.
pub fn fixLight(s: FixStats) Light {
    if (s.with_tests == s.fixes) return .green;
    // with_tests / fixes >= 0.8, sem divisão
    return if (s.with_tests * 5 >= s.fixes * 4) .yellow else .red;
}

test "semáforos: limites do PLANO.md" {
    const t = std.testing;
    try t.expectEqual(.green, coverageLight(90.0));
    try t.expectEqual(.yellow, coverageLight(89.9));
    try t.expectEqual(.yellow, coverageLight(80.0));
    try t.expectEqual(.red, coverageLight(79.9));

    try t.expectEqual(.green, complexityLight(10));
    try t.expectEqual(.yellow, complexityLight(11));
    try t.expectEqual(.yellow, complexityLight(15));
    try t.expectEqual(.red, complexityLight(16));

    try t.expectEqual(.green, magicLight(0));
    try t.expectEqual(.yellow, magicLight(1));
    try t.expectEqual(.yellow, magicLight(5));
    try t.expectEqual(.red, magicLight(6));

    try t.expectEqual(.green, fixLight(.{}));
    try t.expectEqual(.green, fixLight(.{ .fixes = 5, .with_tests = 5 }));
    try t.expectEqual(.yellow, fixLight(.{ .fixes = 5, .with_tests = 4 }));
    try t.expectEqual(.red, fixLight(.{ .fixes = 10, .with_tests = 7 }));
}

/// Motivos para reprovar o `zig build quality`. Vazio: passou.
pub fn failures(arena: std.mem.Allocator, in: Inputs) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    const n_systems = in.analysis.system_violations.len;
    if (n_systems > 0) try list.append(arena, try std.fmt.allocPrint(arena, "{d} import(s) entre sistemas", .{n_systems}));
    if (in.analysis.cycle != null) try list.append(arena, "ciclo de imports");
    if (!in.mutation.baseline_ok) try list.append(arena, "os testes falham sem mutação; a mutação não foi medida");
    const n_survivors = in.mutation.survivors.len;
    if (n_survivors > 0) try list.append(arena, try std.fmt.allocPrint(arena, "{d} mutante(s) sobrevivente(s)", .{n_survivors}));
    const n_missing = in.mutation.missing_reason.len;
    if (n_missing > 0) try list.append(arena, try std.fmt.allocPrint(arena, "{d} `// mutation: disable` sem motivo", .{n_missing}));
    return list.items;
}

test "failures: cada regra que reprova vira um motivo" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ok: Inputs = .{
        .analysis = .{},
        .mutation = .{ .baseline_ok = true },
        .coverage = &.{},
        .fixes = .{},
    };
    try std.testing.expectEqual(0, (try failures(a, ok)).len);

    var bad = ok;
    bad.analysis.system_violations = &.{.{ .from = "systems/a.zig", .to = "systems/b.zig" }};
    bad.analysis.cycle = &.{ "a.zig", "b.zig", "a.zig" };
    bad.mutation.survivors = &.{.{ .path = "health.zig", .line = 3, .description = "x" }};
    bad.mutation.missing_reason = &.{.{ .path = "health.zig", .line = 9 }};
    try std.testing.expectEqual(4, (try failures(a, bad)).len);

    var no_baseline = ok;
    no_baseline.mutation.baseline_ok = false;
    try std.testing.expectEqual(1, (try failures(a, no_baseline)).len);
}

pub const block_begin = "<!-- quality:begin (gerado pelo zig build quality; não editar à mão) -->";
pub const block_end = "<!-- quality:end -->";

/// Troca o que está entre os marcadores por `block`. Sem marcadores, acrescenta no fim.
pub fn replaceBlock(arena: std.mem.Allocator, doc: []const u8, block: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, doc, block_begin)) |begin| {
        if (std.mem.indexOfPos(u8, doc, begin, block_end)) |end| {
            const head = doc[0 .. begin + block_begin.len];
            return std.mem.concat(arena, u8, &.{ head, "\n", block, doc[end..] });
        }
    }
    return std.mem.concat(arena, u8, &.{ doc, "\n", block_begin, "\n", block, block_end, "\n" });
}

test "replaceBlock: troca só o trecho entre os marcadores" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const doc = "# Medições\n\n" ++ block_begin ++ "\nvelho\n" ++ block_end ++ "\n\n## Fase 0\n";
    try std.testing.expectEqualStrings(
        "# Medições\n\n" ++ block_begin ++ "\nnovo\n" ++ block_end ++ "\n\n## Fase 0\n",
        try replaceBlock(arena.allocator(), doc, "novo\n"),
    );
}

test "replaceBlock: sem marcadores, acrescenta o bloco no fim" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings(
        "# Medições\n\n" ++ block_begin ++ "\nnovo\n" ++ block_end ++ "\n",
        try replaceBlock(arena.allocator(), "# Medições\n", "novo\n"),
    );
}

/// O relatório em markdown: o mesmo texto vai para o terminal, o Job Summary
/// do GitHub Actions e o `docs/medicoes.md`.
pub fn render(arena: std.mem.Allocator, in: Inputs) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    const w = &out.writer;
    const fails = try failures(arena, in);

    try w.writeAll("## Qualidade (`zig build quality`)\n\n");
    if (fails.len == 0) {
        try w.writeAll("**Resultado: ✅ passou**\n\n");
    } else {
        try w.writeAll("**Resultado: ❌ reprovou**\n\n");
        for (fails) |f| try w.print("- {s}\n", .{f});
        try w.writeAll("\n");
    }

    try renderPillars(w, in);
    try renderTests(w, in);
    try renderDetails(arena, w, in);
    return out.written();
}

fn pass(ok: bool) []const u8 {
    return if (ok) "✅" else "❌";
}

fn renderPillars(w: *std.Io.Writer, in: Inputs) !void {
    const a = in.analysis;
    try w.writeAll("### Pilares\n\n| Pilar | Indicador | Valor | Regra |\n|---|---|---|---|\n");
    try w.print("| Modular | Imports entre sistemas | {s} {d} | Reprova se houver |\n", .{ pass(a.system_violations.len == 0), a.system_violations.len });
    try w.print("| Modular | Ciclos de imports | {s} {s} | Reprova se houver |\n", .{ pass(a.cycle == null), if (a.cycle == null) "nenhum" else "há ciclo" });
    try w.print("| Modular | Lógica testável sem engine | {s} testes rodam sem a raylib | Reprova se não compilar |\n", .{pass(in.mutation.baseline_ok)});
    try w.print("| Editável | Números mágicos em `src/` | {s} {d} | 🟢 0 · 🟡 1–5 · 🔴 > 5 |\n", .{ magicLight(a.magic.len).emoji(), a.magic.len });
    try w.writeAll("| Editável | Dados válidos | ⏳ ainda não há `data/*.zon` (fase 3) | Reprova se falhar |\n");
    try w.writeAll("| Depurável | Determinismo (mesma seed, mesmo hash) | ⏳ ainda não há mundo (fase 2) | Reprova se diferir |\n");
    try w.writeAll("| Depurável | Todo evento aparece no debug | ⏳ ainda não há eventos (fase 2) | Reprova no build |\n");
    const f = in.fixes;
    if (f.fixes == 0) {
        try w.writeAll("| Depurável | Commits `fix:` com teste | 🟢 nenhum commit `fix:` ainda | 🟢 100% · 🟡 ≥ 80% · 🔴 < 80% |\n\n");
    } else {
        try w.print("| Depurável | Commits `fix:` com teste | {s} {d}/{d} | 🟢 100% · 🟡 ≥ 80% · 🔴 < 80% |\n\n", .{ fixLight(f).emoji(), f.with_tests, f.fixes });
    }
}

fn renderTests(w: *std.Io.Writer, in: Inputs) !void {
    try w.writeAll("### Testes\n\n| Medição | Valor | Regra |\n|---|---|---|\n");

    var covered: u32 = 0;
    var total: u32 = 0;
    for (in.coverage) |c| {
        covered += c.covered;
        total += c.total;
    }
    if (total == 0) {
        try w.writeAll("| Cobertura (linhas) | — sem linhas de produção | 🟢 ≥ 90% · 🟡 80–90% · 🔴 < 80% |\n");
    } else {
        const pct = percent(covered, total);
        try w.print("| Cobertura (linhas) | {s} {d:.1}% ({d}/{d}) | 🟢 ≥ 90% · 🟡 80–90% · 🔴 < 80% |\n", .{ coverageLight(pct).emoji(), pct, covered, total });
    }

    const m = in.mutation;
    if (m.baseline_ok) {
        try w.print("| Mutação | {s} {d} sobrevivente(s); {d} morto(s), {d} por tempo esgotado, {d} não compilou, {d} desativado(s) | Todo sobrevivente reprova |\n", .{ pass(m.survivors.len == 0), m.survivors.len, m.killed, m.timeout, m.no_compile, m.disabled });
    } else {
        try w.writeAll("| Mutação | ❌ não medida: os testes falham sem mutação | Todo sobrevivente reprova |\n");
    }

    if (mostComplex(in.analysis.functions)) |top| {
        try w.print("| Complexidade (maior) | {s} {d} (`{s}`, `{s}:{d}`) | 🟢 até 10 · 🟡 11–15 · 🔴 > 15 |\n\n", .{ complexityLight(top.score).emoji(), top.score, top.name, top.path, top.line });
    } else {
        try w.writeAll("| Complexidade (maior) | — sem funções | 🟢 até 10 · 🟡 11–15 · 🔴 > 15 |\n\n");
    }
}

fn renderDetails(arena: std.mem.Allocator, w: *std.Io.Writer, in: Inputs) !void {
    const m = in.mutation;
    if (m.survivors.len > 0) {
        try w.writeAll("### Mutantes sobreviventes\n\nCada um precisa de um teste que o mate, ou de `// mutation: disable — <motivo>`.\n\n");
        for (m.survivors) |s| try w.print("- `{s}:{d}`: {s}\n", .{ s.path, s.line, s.description });
        try w.writeAll("\n");
    }
    for (m.missing_reason) |p| try w.print("- `{s}:{d}`: `// mutation: disable` sem motivo\n", .{ p.path, p.line });

    const a = in.analysis;
    for (a.system_violations) |e| try w.print("- Import entre sistemas: `{s}` → `{s}`\n", .{ e.from, e.to });
    if (a.cycle) |cycle| {
        try w.writeAll("- Ciclo de imports: ");
        for (cycle, 0..) |path, i| try w.print("{s}`{s}`", .{ if (i == 0) "" else " → ", path });
        try w.writeAll("\n");
    }
    if (a.magic.len > 0) {
        try w.writeAll("### Números mágicos\n\n");
        for (a.magic) |n| try w.print("- `{s}:{d}`: `{s}`\n", .{ n.path, n.line, n.text });
        try w.writeAll("\n");
    }

    if (in.coverage.len > 0) {
        try w.writeAll("### Cobertura por arquivo\n\n| Arquivo | Linhas | Cobertura |\n|---|---|---|\n");
        for (in.coverage) |c| {
            const pct = if (c.total == 0) 100.0 else percent(c.covered, c.total);
            try w.print("| `{s}` | {d}/{d} | {s} {d:.1}% |\n", .{ c.path, c.covered, c.total, coverageLight(pct).emoji(), pct });
        }
        try w.writeAll("\n");
    }

    try w.writeAll("### Funções mais complexas\n\n| Função | Onde | Complexidade |\n|---|---|---|\n");
    for (try topComplex(arena, a.functions)) |f| {
        try w.print("| `{s}` | `{s}:{d}` | {s} {d} |\n", .{ f.name, f.path, f.line, complexityLight(f.score).emoji(), f.score });
    }
}

fn percent(part: u32, whole: u32) f64 {
    return @as(f64, @floatFromInt(part)) * 100.0 / @as(f64, @floatFromInt(whole));
}

fn mostComplex(fns: []const analyze.Report.FileFn) ?analyze.Report.FileFn {
    var top: ?analyze.Report.FileFn = null;
    for (fns) |f| {
        if (top == null or f.score > top.?.score) top = f;
    }
    return top;
}

const top_count = 5;

/// As `top_count` funções mais complexas, da maior para a menor.
fn topComplex(arena: std.mem.Allocator, fns: []const analyze.Report.FileFn) ![]const analyze.Report.FileFn {
    const sorted = try arena.dupe(analyze.Report.FileFn, fns);
    std.mem.sort(analyze.Report.FileFn, sorted, {}, moreComplex);
    return sorted[0..@min(top_count, sorted.len)];
}

fn moreComplex(_: void, a: analyze.Report.FileFn, b: analyze.Report.FileFn) bool {
    return a.score > b.score;
}

test "render: mostra resultado, cobertura com semáforo e sobreviventes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var in: Inputs = .{
        .analysis = .{ .functions = &.{.{ .path = "health.zig", .name = "heal", .line = 22, .score = 12 }} },
        .mutation = .{ .baseline_ok = true, .killed = 3 },
        .coverage = &.{.{ .path = "health.zig", .covered = 9, .total = 10 }},
        .fixes = .{},
    };
    const ok = try render(a, in);
    try std.testing.expect(std.mem.indexOf(u8, ok, "✅ passou") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok, "🟢 90.0% (9/10)") != null);
    try std.testing.expect(std.mem.indexOf(u8, ok, "🟡 12") != null);

    in.mutation.survivors = &.{.{ .path = "health.zig", .line = 18, .description = "`-|=` → `+|=`" }};
    const bad = try render(a, in);
    try std.testing.expect(std.mem.indexOf(u8, bad, "❌ reprovou") != null);
    try std.testing.expect(std.mem.indexOf(u8, bad, "`health.zig:18`") != null);
}
