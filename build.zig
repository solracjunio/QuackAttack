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

    const exe = b.addExecutable(.{ .name = "quackatack", .root_module = exe_mod });
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

    // `test` roda tudo; por enquanto só existe a lógica.
    const test_step = b.step("test", "Roda todos os testes");
    test_step.dependOn(headless_step);
}
