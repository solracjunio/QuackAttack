const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Lógica do jogo: não conhece a raylib, por isso roda sem janela.
    const game = b.addModule("game", .{
        .root_source_file = b.path("src/game.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Executável: só ele importa a raylib.
    const raylib_dep = b.dependency("raylib_zig", .{ .target = target, .optimize = optimize });
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "game", .module = game },
            .{ .name = "raylib", .module = raylib_dep.module("raylib") },
        },
    });
    exe_mod.linkLibrary(raylib_dep.artifact("raylib"));

    const exe = b.addExecutable(.{ .name = "quackattack", .root_module = exe_mod });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    b.step("run", "Abre o jogo").dependOn(&run_cmd.step);

    // Testes da lógica, sem linkar a raylib (pilar Modular).
    const game_tests = b.addTest(.{ .root_module = game });
    const run_game_tests = b.addRunArtifact(game_tests);

    const headless_step = b.step("test-headless", "Testes da lógica, sem raylib");
    headless_step.dependOn(&run_game_tests.step);

    // `test` roda tudo: a lógica e os testes das ferramentas de qualidade.
    const test_step = b.step("test", "Roda todos os testes");
    test_step.dependOn(headless_step);
    for (quality_tools) |name| {
        const tool_tests = b.addTest(.{ .root_module = toolModule(b, name) });
        test_step.dependOn(&b.addRunArtifact(tool_tests).step);
    }

    addQualityStep(b, target);
}

const quality_tools = [_][]const u8{ "source", "analyze", "mutate", "report" };

/// Segundos que cada mutante tem para rodar os testes (pega laço infinito).
const mutant_timeout_seconds = "60";

fn toolModule(b: *std.Build, name: []const u8) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.path(b.fmt("tools/{s}.zig", .{name})),
        .target = b.graph.host,
    });
}

fn tool(b: *std.Build, name: []const u8) *std.Build.Step.Compile {
    return b.addExecutable(.{ .name = name, .root_module = toolModule(b, name) });
}

/// `zig build quality`: imports, números mágicos, complexidade, cobertura
/// (kcov), mutação e commits `fix:`. Gera o relatório e reprova se precisar.
/// As ferramentas leem `src/` direto do disco, por isso rodam sempre
/// (`has_side_effects`), sem depender do cache do build.
fn addQualityStep(b: *std.Build, target: std.Build.ResolvedTarget) void {
    const src = b.path("src");
    const absolute: std.Build.Step.Run.PathArgOptions = .{ .make_absolute = true };

    const analyze = b.addRunArtifact(tool(b, "analyze"));
    analyze.addDirectoryArg2(src, absolute);
    const analysis = analyze.addOutputFileArg("analyze.zon");
    analyze.has_side_effects = true;

    // Cobertura: o kcov só lê o binário compilado pelo LLVM.
    const coverage_tests = b.addTest(.{
        .name = "coverage",
        .root_module = b.createModule(.{ .root_source_file = b.path("src/game.zig"), .target = target }),
        .use_llvm = true,
    });
    const kcov = b.addSystemCommand(&.{"kcov"});
    kcov.addDirectoryArg2(src, .{ .prefix = "--include-path=", .make_absolute = true });
    const kcov_dir = kcov.addOutputDirectoryArg("kcov");
    kcov.addArtifactArg(coverage_tests);
    kcov.has_side_effects = true;

    const mutate = b.addRunArtifact(tool(b, "mutate"));
    mutate.addArg(b.graph.zig_exe);
    mutate.addDirectoryArg2(src, absolute);
    mutate.addArg("game.zig");
    _ = mutate.addOutputDirectoryArg("workspace");
    const mutation = mutate.addOutputFileArg("mutate.zon");
    mutate.addArg(mutant_timeout_seconds);
    mutate.has_side_effects = true;

    const git_log = b.addSystemCommand(&.{ "git", "log", "--format=%x1e%s", "-p", "--unified=0" });
    git_log.setCwd(b.path("."));
    git_log.has_side_effects = true;
    const log = git_log.captureStdOut(.{});

    const report = b.addRunArtifact(tool(b, "report"));
    report.addFileArg(analysis);
    report.addFileArg(kcov_dir.path(b, "coverage/cobertura.xml"));
    report.addFileArg(mutation);
    report.addFileArg(log);
    report.addDirectoryArg2(src, absolute);
    report.addFileArg2(b.path("docs/medicoes.md"), absolute);
    report.has_side_effects = true;

    b.step("quality", "Métricas de qualidade com semáforo; reprova pelas regras do PLANO.md").dependOn(&report.step);
}
