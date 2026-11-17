# Medições

Métricas de cada fase, para o post. Ver "O que medir" no `PLANO.md`.

## Fase 0: Setup

| Medição | Valor |
|---|---|
| Tempo gasto | _a preencher_ |
| Prompts ao Claude | 2 (devbox; repositório + fase 0) |
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
