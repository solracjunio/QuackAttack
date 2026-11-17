# QuackAtack

Roguelite de fila em Zig com raylib-zig. O plano completo e o escopo estão em `PLANO.md`.

## Versão do Zig: 0.17.0

- Documentação da linguagem: https://ziglang.org/documentation/0.17.0/
- Documentação da std: https://ziglang.org/documentation/0.17.0/std/
- A std muda muito entre versões. **Antes de usar uma API da std, confira na fonte local**, que é sempre a versão certa:
  `grep -rn "pub fn nome" "$(zig env | sed -n 's/.*\.std_dir = "\(.*\)".*/\1/p')"`
- Pontos que mudaram e costumam sair errados:
  - `main` recebe `std.process.Init` (`pub fn main(init: std.process.Init) !void`), que traz `init.io`, `init.arena`, os argumentos etc. Um `main` sem parâmetros também vale.
  - I/O passa por `std.Io` (`init.io`); escrita por `std.Io.Writer` com buffer e `flush()`.
  - `std.ArrayList(T)` não guarda o allocator: comece com `.empty` e passe o allocator em cada chamada (`append(gpa, x)`, `deinit(gpa)`).
  - No `build.zig`: `b.createModule` / `b.addModule` com `root_module`; argumentos do `zig build run -- ...` via `run_cmd.addPassthruArgs()`.
- raylib-zig fixado num commit do ramo `devel` (raylib 6.2) no `build.zig.zon`. Para ver a API: `zig-pkg/raylib_zig-*/lib/raylib.zig`.

## Ambiente

- Tudo roda dentro do `devbox shell` (Zig, kcov, X11/OpenGL e Mesa vêm do `devbox.json`).
- O projeto está em disco do Windows (`/mnt/g`), onde o Zig não consegue renomear arquivos no `.zig-cache`. Por isso o `init_hook` define `ZIG_LOCAL_CACHE_DIR` no disco do Linux. Se aparecer `AccessDenied` ao renomear, confira se essa variável está definida.
- Cobertura com kcov: o binário de teste precisa ser compilado com LLVM (`use_llvm = true`). Com o backend próprio do Zig, o kcov mostra 0%.

## Comandos

- `zig build test`: todos os testes. **Rodar antes de dar qualquer tarefa por terminada.**
- `zig build test-headless`: só a lógica, sem linkar a raylib.
- `zig build run`: abre o jogo.
- `zig fmt --check build.zig src/`: formatação (o CI também confere).

## Regras

- Escopo: só o que está em "O jogo (MVP)" do `PLANO.md`. O jogo existe só para testar a ideia e escrever o post.
- TDD: teste falhando primeiro (pela asserção, não por erro de compilação), depois o mínimo para passar, depois refatorar. Toda lógica nova vem com teste.
- Os testes ficam no mesmo arquivo do código (`test "cenário: resultado esperado" { ... }`), como é o normal em Zig. Todo arquivo de lógica é importado em `src/game.zig` para os testes dele rodarem.
- A lógica (`src/game.zig` e o que ele importa) **nunca** importa a raylib. Só `main.zig` e `src/ui/` usam a raylib.
- Nenhum número de balanceamento no código: tudo em `data/`. Números de tela (tamanho da janela, fonte) podem ficar em `main.zig` e `ui/`.
- Sistemas não chamam uns aos outros: a comunicação é só pela fila de eventos.
- Entidades são referenciadas por handle (index + generation), nunca por ponteiro guardado.
- Um sistema por arquivo em `src/systems/`; `main.zig` só orquestra.
- Encapsulamento: o Zig não tem campos privados. Campo marcado "somente leitura fora deste arquivo" só muda pelas funções do próprio módulo (ex.: `health.zig`).
- Depois que `zig build quality` existir: rodar e informar cobertura, mutação e a função mais complexa ao terminar uma tarefa.
- Mutante sobrevivente: escrever o teste que o mata, ou comentar `// mutation: disable — <motivo>`. Nunca desativar sem motivo.
- Função acima de 10 de complexidade é candidata a refatorar; acima de 15, avisar.
- Toda vez que eu (Claude) escrever API de Zig de outra versão, anotar em `docs/medicoes.md`. Isso é uma métrica do post.
