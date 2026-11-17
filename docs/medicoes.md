# Medições

Métricas de cada fase, para o post. Ver "O que medir" no `PLANO.md`.

## Fase 0: Setup

| Medição | Valor |
|---|---|
| Tempo gasto | _a preencher_ |
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
| Tempo gasto | _a preencher_ |
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
| Editável | Dados válidos | ⏳ ainda não há `data/*.zon` (fase 3) | Reprova se falhar |
| Depurável | Determinismo (mesma seed, mesmo hash) | ⏳ ainda não há mundo (fase 2) | Reprova se diferir |
| Depurável | Todo evento aparece no debug | ⏳ ainda não há eventos (fase 2) | Reprova no build |
| Depurável | Commits `fix:` com teste | 🟢 nenhum commit `fix:` ainda | 🟢 100% · 🟡 ≥ 80% · 🔴 < 80% |

### Testes

| Medição | Valor | Regra |
|---|---|---|
| Cobertura (linhas) | 🟢 100.0% (12/12) | 🟢 ≥ 90% · 🟡 80–90% · 🔴 < 80% |
| Mutação | ✅ 0 sobrevivente(s); 3 morto(s), 0 por tempo esgotado, 2 não compilou, 1 desativado(s) | Todo sobrevivente reprova |
| Complexidade (maior) | 🟢 5 (`refAllDeclsRecursive`, `game.zig:11`) | 🟢 até 10 · 🟡 11–15 · 🔴 > 15 |

### Cobertura por arquivo

| Arquivo | Linhas | Cobertura |
|---|---|---|
| `health.zig` | 8/8 | 🟢 100.0% |
| `game.zig` | 4/4 | 🟢 100.0% |

### Funções mais complexas

| Função | Onde | Complexidade |
|---|---|---|
| `refAllDeclsRecursive` | `game.zig:11` | 🟢 5 |
| `main` | `main.zig:8` | 🟢 2 |
| `init` | `health.zig:14` | 🟢 1 |
| `damage` | `health.zig:18` | 🟢 1 |
| `heal` | `health.zig:22` | 🟢 1 |
<!-- quality:end -->
