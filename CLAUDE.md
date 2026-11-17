# QuackAttack

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
  - No `build.zig`: `b.createModule` / `b.addModule` com `root_module`; argumentos do `zig build run -- ...` via `run_cmd.addPassthruArgs()`. Caminhos do projeto: `b.path(...)` (não existe `b.pathFromRoot`).
  - Não existem mais: `std.fmt.bufPrintZ` (use `bufPrintSentinel(buf, fmt, args, 0)`), repetição de array com `**` (use `@splat`), `std.Random.enumValue` (use `enumValueWithIndex`), `std.testing.refAllDeclsRecursive`. `@enumFromInt` virou `@fromBackingInt`.
  - `@Vector(2, f32)` ocupa 16 bytes no backend do Zig e 8 no LLVM; o preenchimento tem lixo. Para hash ou comparação de bytes, use `vec.toArray`.
  - `@min(x, constante)` devolve um inteiro estreito (ex.: `u5`). Dê o tipo do resultado (`const n: usize = @min(...)`) antes de fazer contas.
- raylib-zig fixado num commit do ramo `devel` (raylib 6.2) no `build.zig.zon`. Para ver a API: `zig-pkg/raylib_zig-*/lib/raylib.zig`.

## Ambiente

- Tudo roda dentro do `devbox shell` (Zig, kcov, X11/OpenGL e Mesa vêm do `devbox.json`).
- O projeto está em disco do Windows (`/mnt/g`), onde o Zig não consegue renomear arquivos no `.zig-cache`. Por isso o `init_hook` define `ZIG_LOCAL_CACHE_DIR` no disco do Linux. Se aparecer `AccessDenied` ao renomear, confira se essa variável está definida.
- Cobertura com kcov: o binário de teste precisa ser compilado com LLVM (`use_llvm = true`). Com o backend próprio do Zig, o kcov mostra 0%.

## Comandos

- `zig build test`: todos os testes (lógica e ferramentas). **Rodar antes de dar qualquer tarefa por terminada.**
- `zig build test-headless`: só a lógica, sem linkar a raylib.
- `devbox run windows`: compila o `.exe` do Windows em `zig-out/bin/`. Rode de novo sempre que `data/game.zon` ganhar campos: um `.exe` antigo recusa campos que não conhece. Abra o `.exe` a partir da raiz do projeto (ele lê `data/game.zon`).
- `zig build run`: abre o jogo (←/→ ou A/D giram a líder; F1 liga o overlay de debug).
- `zig build quality`: imports, números mágicos, complexidade, cobertura (kcov), mutação e commits `fix:`. Imprime as tabelas, atualiza o bloco gerado do `docs/medicoes.md` e reprova pelas regras do `PLANO.md`. No CI, as tabelas vão para o *Summary* da execução.
- `zig fmt --check build.zig src/ tools/ data/check.zig`: formatação (o CI também confere).

## Ferramentas de qualidade (`tools/`)

- `source.zig` (AST comum), `analyze.zig`, `mutate.zig`, `report.zig`. Também seguem TDD; os testes delas rodam no `zig build test`.
- `mutate` trabalha numa cópia de `src/` no cache do Zig: o código original nunca é alterado. Cada mutante é compilado (cache próprio, apagado no fim) e o binário roda com `ulimit -v` de 1 GiB e timeout de 10 s (`build.zig`). Não tire esses limites: um mutante que aloca em laço já derrubou o WSL.
- Os operadores de mutação não cobrem tudo (ex.: não removem um `@min`). Mutação limpa não prova que todo comportamento tem teste.
- Exceções com motivo obrigatório (sem motivo, não valem):
  - `// mutation: disable — <motivo>`: só para mutante equivalente (não muda o comportamento).
  - `// magic: allow — <motivo>`: só para número que não é balanceamento (ex.: o `2` de `@Vector(2, f32)`).
  - Os dois valem para a linha deles e a de baixo, **a linha inteira**. Isole a expressão numa linha só (`const x = a <= b;`), senão outros mutantes ou números da linha ficam escondidos.
- `src/game.zig` usa `refAllDeclsRecursive` para o Zig compilar até as funções que nenhum teste chama. Sem isso elas somem da cobertura em vez de aparecer como não cobertas. Todo arquivo de lógica novo precisa ser `pub const` no `game.zig`.

## Regras

- Escopo: só o que está em "O jogo (MVP)" do `PLANO.md`. O jogo existe só para testar a ideia e escrever o post.
- TDD: teste falhando primeiro (pela asserção, não por erro de compilação), depois o mínimo para passar, depois refatorar. Toda lógica nova vem com teste.
- Os testes ficam no mesmo arquivo do código (`test "cenário: resultado esperado" { ... }`), como é o normal em Zig. Todo arquivo de lógica é importado em `src/game.zig` para os testes dele rodarem.
- Ajudas de teste compartilhadas ficam em `src/testing.zig` (ex.: `expectVec`). Números de teste fora de um bloco `test` contam como mágicos: monte os dados dentro do teste ou use `config.example()`.
- Testes de um sistema não importam outro sistema (a regra vale também nos testes): montam o estado direto no `World`.
- Helper de teste com contas ou números: declare dentro do bloco `test` (`const Helper = struct { fn ... };`). Fora dele, a mutação e os números mágicos o tratam como produção.
- Floats nos testes: use valores exatos em binário (0.5, 0.25, 1.5). `1.9 + 0.1` em `f32` não dá `2`.
- Ordem do passo (`src/sim.zig`): limpa os eventos, `mover`, `seguir`, `spawner`, `perseguir`, `mirar`, `atacar`, `magia`, `projeteis`, `contato`, `aplicar_dano`, `limpar_mortos`. Dano e morte só acontecem por eventos (`src/events.zig`); todo tipo de evento novo precisa de texto no `describe`.
- Aleatoriedade só pelo `World.rng` (criado com a `seed` do `data/game.zon`). O teste de determinismo em `sim.zig` reprova se duas partidas iguais divergirem.
- Classes: `data/classes.zon` (nome, aparência e ataque). Classe nova com ataque e acessório que já existem é só uma entrada lá (e, se quiser, um nome em `queue.start_classes`). Ataque novo = variante em `classes.Attack` + regras no `classes.validate` + um sistema que o use. A classe é uma tagged union de ataque; o patinho guarda o índice da classe.
- Relacionamentos (`src/relations.zig`): `(Segue, líder)` e `(Mira, inimigo)`, com consulta por curinga (`query(.mira, .any)`). Todo patinho novo entra por `World.addDuck` (já com `(Segue, líder)`). Quem morre perde as relações que apontam para ele em `limpar_mortos`.
- Fixtures de teste com números podem ficar em `.zon` dentro de `src/` (ex.: `src/example_classes.zon`): o `analyze` só lê `.zig`, e o `mutate` copia todos os arquivos.
- Union também tem bytes de preenchimento com lixo: no hash, entra campo a campo (ver `World.feedEntity`).
- Dados: `data/game.zon` e `data/classes.zon` são lidos quando o jogo abre (mudar não exige recompilar). Todo campo novo entra em `Config` (`src/config.zig`) e, se puder quebrar o jogo, ganha regra no `validate`. O `data/check.zig` confere os arquivos reais, juntos (inclusive as referências entre eles), no `zig build test`.
- **Visual:** tudo o que aparece na tela segue `docs/guia-visual.md` (formas, sombras, paleta, HUD e o checklist de item novo). Cores só de `src/ui/palette.zig`; cor nova entra no guia e na paleta juntas. O desenho do mundo fica em `src/ui/scene.zig`, o HUD em `src/ui/hud.zig`, o brilho em `src/ui/glow.zig` e a montagem em camadas (fundo → brilho → atores) em `src/ui/render.zig`.
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
