# Medições

Os tempos são estimativas do Claude, pelos horários da sessão (passagens de sessão registradas, pushes e execuções do CI). Contam o tempo de relógio do trabalho, não o de leitura e revisão.

Métricas de cada fase, para o post. Ver "O que medir" no `PLANO.md`.

## Fase 0: Setup

| Medição | Valor |
|---|---|
| Tempo gasto | ~20 min (devbox ~10 min + fase 0 ~10 min) |
| API de Zig de outra versão escrita pelo Claude | 0 (o esqueleto do `zig init` 0.17 foi lido antes de escrever código) |
| Testes | 6 (`health.zig`) |
| Bugs pegos pelos testes | 0 |

### Notas para o post

- **Ambiente (devbox + Nix no WSL):** dois problemas antes da primeira linha de jogo:
  1. O OpenGL do Nix não acha o driver fora do NixOS ("No GLXFBConfigs"). Solução: Mesa do Nix com o driver `d3d12` do WSLg.
  2. Com o projeto em disco do Windows (`/mnt/g`), o Zig não consegue renomear no `.zig-cache` (`AccessDenied`). Solução: `ZIG_LOCAL_CACHE_DIR` no disco do Linux.
- **kcov:** mostra 0% com o backend próprio do Zig; precisa de `-fllvm`.
- **TDD em Zig:** chamar uma função que não existe é erro de compilação, não teste falhando. Para o Red falhar pela asserção, a função nasce com um corpo provisório.
- **O Zig pegou o bug sozinho:** no ciclo "dano maior que a vida", o `-=` em `u32` deu `integer overflow` no modo debug. O conserto foi a subtração saturada `-|=`.
- **Encapsulamento:** o Zig não tem campos privados. A regra "a vida só muda pelo `health.zig`" depende de convenção (comentário "somente leitura"). Ponto para avaliar no post.

## Ferramentas: `zig build quality`

| Medição | Valor |
|---|---|
| Tempo gasto | ~30 min |
| API de Zig de outra versão escrita pelo Claude | 2: `@enumFromInt` (o `zig fmt` do 0.17 trocou por `@fromBackingInt`) e `b.pathFromRoot` no `build.zig` (não existe mais; o certo é `LazyPath` com `addDirectoryArg2(..., .{ .make_absolute = true })`) |
| Quase-erros (conferidos na std antes de escrever) | `std.fs.path.resolve` → `resolveAlloc`; `std.testing.refAllDeclsRecursive` não existe mais; `captureStdOut` agora recebe opções |
| Testes das ferramentas | 25 (source 3, analyze 9, mutate 6, report 7) |
| Tempo do `zig build quality` | ~6 s |

### Notas para o post

- **Mutação nas próprias ferramentas:** rodar o `mutate` sobre `tools/` deixou 27 sobreviventes. A maioria era código de disco e processo sem teste de unidade (`main`, `Runner`) ou mutante equivalente (ex.: `last + 1` → `last - 1` quando o último token é sempre `}`). Um era lacuna real: os limites do `inTest`, que ganharam teste.
- **Primeiro `// mutation: disable` com motivo:** no `refAllDeclsRecursive` do `game.zig`, trocar `==` por `!=` não quebra nenhum teste, porque essa função só decide o que entra na cobertura.
- **Cobertura enganosa no Zig:** o Zig só compila o que é usado. Sem o `refAllDeclsRecursive`, uma função pública sem teste não aparece no kcov, e a cobertura sobe em vez de cair.
- **Limite dos operadores:** apagar o teste "a cura para no máximo" não deixou mutante vivo, porque nenhum operador remove o `@min`. A cobertura também continuou 100%. Esse comportamento só está protegido porque o teste existe.
- **Prova de que reprova:** sem os dois testes de cura, o `quality` saiu com código 1, apontou `health.zig:23: +| → -|` e a cobertura caiu para 🟡 83%.

## Fase 1: Fila

| Medição | Valor |
|---|---|
| Tempo gasto | ~25 min |
| API de Zig de outra versão escrita pelo Claude | 0 |
| Testes da lógica | 34, mais 1 do `data/check.zig` (eram 6) |
| Bugs pegos pelos testes | 1: `pointAt` dava NaN com dois pontos iguais seguidos (`0/0`) |
| Mutantes sobreviventes no primeiro `quality` | 8 → 0 |

### Notas para o post

- **O que a mutação achou:** dos 8 sobreviventes, 5 eram testes faltando (bordas da reflexão, `turn_speed = 0`, `prune` além do caminho), 1 era uma regra redundante no `validate` (o mundo > 0 já é garantido por "a líder cabe no mundo") e 1 era equivalente de verdade (`<` e `<=` dão o mesmo ponto no `pointAt`).
- **Um teste fraco que passava:** o teste da reflexão usava `pos = 0` depois de andar, e com isso `12 + (12 - 0)` e `12 + (12 + 0)` dão o mesmo. Trocar os números fez o mutante morrer.
- **O comentário de exceção escondia mutantes:** o `// mutation: disable` vale para a linha inteira, e a linha tinha também um `+` sem teste. Isolar a comparação numa linha só fez o `+` aparecer, e ele morreu.
- **Ferramentas melhoradas pelo uso:** coluna no mutante (dois `<` na mesma linha ficavam ambíguos) e o `// magic: allow — <motivo>` no `analyze`.
- **Números mágicos em helpers de teste:** os helpers ficam fora dos blocos `test`, então a tolerância `1e-3` e os pontos de exemplo contavam como mágicos. A solução foi um `src/testing.zig` com uma tolerância só e os dados de exemplo montados dentro dos testes.
- **Zig, vetores:** `@Vector(2, f32)` soma e multiplica sem código extra, mas o índice precisa ser conhecido em tempo de compilação e não dá para tirar um `*f32` de um elemento. A reflexão foi escrita por eixo (`axis` comptime).
- **Vazamento em erro:** `std.testing.checkAllAllocationFailures` faz cada alocação falhar uma vez. Sem o `errdefer` no `World.init`, ele acusa o vazamento.

## Fase 2: Inimigos e combate

| Medição | Valor |
|---|---|
| Tempo gasto | ~35 min |
| API de Zig de outra versão escrita pelo Claude | 2: repetição de array com `**` (virou `@splat`) e `std.fmt.bufPrintZ` (virou `bufPrintSentinel`) |
| Testes da lógica | 83, mais 1 do `data/check.zig` (eram 34) |
| Bugs pegos pelos testes | 1: o `hash()` lia o lixo do preenchimento do `@Vector`, e duas partidas iguais davam hashes diferentes |
| Bugs que só apareceram rodando o jogo | 1: `integer overflow` no overlay de debug (`@min` com constante devolve `u5`) |
| Mutantes sobreviventes no primeiro `quality` | 11 → 0 |
| Tempo do `zig build quality` | ~3 min (eram ~6 s): 156 mutantes, cada um compila os testes |
| Incidentes | 1: um mutante derrubou o WSL por falta de memória (ver abaixo) |

### Notas para o post

- **O teste de determinismo pagou o custo no primeiro dia.** Duas partidas com a mesma seed e a mesma entrada divergiam já no passo 0. A causa não estava na simulação: `@Vector(2, f32)` ocupa 16 bytes no backend do Zig, e os 8 de alinhamento têm lixo. O `hash()` lia os bytes crus. Sem o teste, isso viraria "o replay às vezes não bate" na fase de depuração.
- **E o tamanho depende do backend:** no build de cobertura (LLVM) o mesmo vetor ocupa 8 bytes. Um teste que presumia o tamanho passou nos testes normais e falhou só no kcov.
- **Eventos como objetos funcionaram sem esforço:** `projeteis` e `contato` só acrescentam `damage`; `aplicar_dano` gera `died`; `limpar_mortos` remove. Nenhum sistema importa outro. Dois tiros mortais no mesmo passo geram um `died` só, porque `aplicar_dano` só emite na passagem de vivo para morto.
- **Handle com geração na prática:** um evento com handle de um inimigo que já saiu (e cuja vaga foi reaproveitada) é ignorado, não acerta o inimigo novo. Tem teste para isso.
- **Variáveis observáveis ainda não fizeram falta:** o HUD e o overlay leem o `World` direto, a cada frame.
- **O que a mutação achou desta vez:** testes com posição aleatória não pegavam os cantos do spawner (a solução foi separar `pointOnSide` e testar `t = 0` e `t = 1`); um helper de teste fora do bloco `test` era mutado como se fosse produção; e um equivalente real em `perseguir` (`dist == step` chega na líder pelos dois caminhos).
- **Custo da mutação:** com 156 mutantes, o `quality` passou de segundos para ~4 minutos. Ainda dá para rodar antes de cada commit.
- **Um mutante derrubou o WSL.** Trocar `spawn_timer += interval` por `-=` no `spawner` faz o `while` criar inimigos para sempre. Com 60 s de timeout por mutante, ele chegou a 5,8 GB (medido depois, com teto); somado à compilação LLVM da cobertura rodando em paralelo, encheu os 16 GB do WSL. Correção no `mutate`: compilar sem limite e rodar o binário com `ulimit -v` de 1 GiB e timeout de 10 s. No `quality` seguinte, a memória livre não passou de 13,2 GB para baixo. Lição: teste de mutação roda código quebrado de propósito; precisa de teto de memória, não só de tempo.
- **E enchia o disco:** cada mutante era compilado no cache principal do Zig, e as saídas ficavam para sempre (18 GB depois de algumas execuções). Agora os mutantes usam um cache próprio na pasta de trabalho, apagado no fim (o cache ficou em ~240 MB).
- **Floats em teste:** `1.9 + 0.1` em `f32` não fecha em `2`, e o spawner "atrasava" um passo. O código estava certo; o teste passou a usar valores exatos em binário.

## Fase 3: Dados e classes

| Medição | Valor |
|---|---|
| Tempo gasto | ~30 min |
| API de Zig de outra versão escrita pelo Claude | 0 |
| Testes da lógica | 111, mais 1 do `data/check.zig` (eram 83) |
| Bugs pegos pelos testes | 0 |
| Mutantes sobreviventes no primeiro `quality` completo | 1 → 0 |
| **Arquivos tocados pelo mago** (pilar: no máximo 2) | **7** (ver abaixo) |

### O mago e o pilar "classe nova toca no máximo 2 arquivos"

O mago tocou 7 arquivos, porque trouxe **comportamento novo** (ataque em área) e **acessório novo** (chapéu de mago):

1. `data/classes.zon`: a entrada do mago;
2. `src/example_classes.zon`: o mago de exemplo dos testes;
3. `src/classes.zig`: a variante `area` do `Attack` e as regras dela no `validate`;
4. `src/systems/magia.zig`: o sistema novo;
5. `src/sim.zig`: chamar o sistema no passo;
6. `src/game.zig`: expor o sistema para os testes rodarem;
7. `src/ui/scene.zig`: o chapéu de mago e o anel do feitiço.

Já uma classe que **reaproveita** um ataque e um acessório (por exemplo, um "besteiro" com mais alcance e menos cadência) toca **1 arquivo**: o `data/classes.zon`. O pilar vale para variações de classe, mas não para comportamento novo: em Zig, sem registro dinâmico de sistemas, cada comportamento novo precisa ser ligado no `sim.zig` e exposto no `game.zig`.

### Notas para o post

- **Relacionamentos com curinga** ficaram pequenos (`src/relations.zig`, uma lista de `(tipo, fonte, alvo)`). O `seguir` consulta `(Segue, líder)`; o `mirar` mantém `(Mira, inimigo)`; o `limpar_mortos` usa a consulta por alvo para achar quem mirava no morto; o overlay mostra `query(.mira, .any)`. A geração do handle vale também nas relações: um inimigo novo na vaga do antigo não herda os atiradores.
- **Mirar separado de atacar:** com o alvo guardado como relação, o arqueiro passou a manter o alvo enquanto ele está no alcance, em vez de trocar a cada tiro. Escolher o alvo (`mirar`) e atirar (`atacar`) viraram dois sistemas que não se conhecem.
- **Union também tem lixo no preenchimento:** a mesma lição do `@Vector` na fase 2. A entidade `.leader` não tem conteúdo, e os bytes do conteúdo ficam com lixo; no hash, a entidade entra campo a campo.
- **Fixtures em `.zon`:** as classes de exemplo dos testes ficaram num `.zon` dentro de `src/`. O `analyze` não conta números de `.zon`, e o Zig importa o arquivo com o tipo certo em tempo de compilação. Mas o `mutate` só copiava `.zig`, e a linha de base passou a falhar; agora ele copia tudo.
- **Números mágicos em helpers de teste de novo:** 22, todos de posições de teste em helpers fora dos blocos `test`. A regra já estava no `CLAUDE.md`; o conserto foi passar as posições como argumento.

<!-- quality:begin (gerado pelo zig build quality; não editar à mão) -->
## Qualidade (`zig build quality`)

**Resultado: ✅ passou**

### Pilares

| Pilar | Indicador | Valor | Regra |
|---|---|---|---|
| Modular | Imports entre sistemas | ✅ 0 | Reprova se houver |
| Modular | Ciclos de imports | ✅ nenhum | Reprova se houver |
| Modular | Lógica testável sem engine | ✅ testes rodam sem a raylib | Reprova se não compilar |
| Editável | Números mágicos em `src/` | 🟢 0 | 🟢 0 · 🟡 1–5 · 🔴 > 5 |
| Editável | Dados válidos | ✅ `data/check.zig` passou | Reprova se falhar |
| Depurável | Determinismo (mesma seed, mesmo hash) | ✅ teste de `sim.zig` | Reprova se diferir |
| Depurável | Todo evento aparece no debug | ✅ `switch` exaustivo em `events.describe` | Reprova no build |
| Depurável | Commits `fix:` com teste | 🟢 1/1 | 🟢 100% · 🟡 ≥ 80% · 🔴 < 80% |

### Testes

| Medição | Valor | Regra |
|---|---|---|
| Cobertura (linhas) | 🟢 100.0% (546/546) | 🟢 ≥ 90% · 🟡 80–90% · 🔴 < 80% |
| Mutação | ✅ 0 sobrevivente(s); 141 morto(s), 1 por tempo esgotado, 75 não compilou, 3 desativado(s) | Todo sobrevivente reprova |
| Complexidade (maior) | 🟢 7 (`hash`, `world.zig:108`) | 🟢 até 10 · 🟡 11–15 · 🔴 > 15 |

### Cobertura por arquivo

| Arquivo | Linhas | Cobertura |
|---|---|---|
| `testing.zig` | 5/5 | 🟢 100.0% |
| `config.zig` | 41/41 | 🟢 100.0% |
| `classes.zig` | 28/28 | 🟢 100.0% |
| `events.zig` | 10/10 | 🟢 100.0% |
| `sim.zig` | 13/13 | 🟢 100.0% |
| `systems/mover.zig` | 21/21 | 🟢 100.0% |
| `trail.zig` | 28/28 | 🟢 100.0% |
| `systems/seguir.zig` | 8/8 | 🟢 100.0% |
| `systems/spawner.zig` | 17/17 | 🟢 100.0% |
| `world.zig` | 75/75 | 🟢 100.0% |
| `game.zig` | 5/5 | 🟢 100.0% |
| `systems/aplicar_dano.zig` | 26/26 | 🟢 100.0% |
| `systems/perseguir.zig` | 17/17 | 🟢 100.0% |
| `health.zig` | 8/8 | 🟢 100.0% |
| `vec.zig` | 12/12 | 🟢 100.0% |
| `systems/limpar_mortos.zig` | 5/5 | 🟢 100.0% |
| `relations.zig` | 45/45 | 🟢 100.0% |
| `pool.zig` | 43/43 | 🟢 100.0% |
| `systems/atacar.zig` | 30/30 | 🟢 100.0% |
| `systems/contato.zig` | 27/27 | 🟢 100.0% |
| `systems/magia.zig` | 23/23 | 🟢 100.0% |
| `systems/projeteis.zig` | 24/24 | 🟢 100.0% |
| `systems/mirar.zig` | 35/35 | 🟢 100.0% |

### Funções mais complexas

| Função | Onde | Complexidade |
|---|---|---|
| `hash` | `world.zig:108` | 🟢 7 |
| `Pool` | `pool.zig:8` | 🟢 6 |
| `update` | `systems/aplicar_dano.zig:7` | 🟢 6 |
| `update` | `systems/atacar.zig:11` | 🟢 6 |
| `anyContact` | `systems/contato.zig:15` | 🟢 6 |
<!-- quality:end -->
