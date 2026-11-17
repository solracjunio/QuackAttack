# Retrospectiva do MVP

Fecho da fase 5 do `PLANO.md`: números finais, os 3 pilares, as ideias de
"O essencial de SOAP, ECS e OOP" na prática, e a comparação com as versões
Spaghetti, SOAP e ECS da série (repositório ROG). Material para o post
"Explorando Arquiteturas, parte X: o essencial em Zig com o Claude Code".

## Resumo

- **O MVP está completo e jogável:** fila que anda como cobra, arqueiro e mago,
  ondas vindas de dados, patinho novo a cada onda, fim de jogo e recomeço.
- **7 de 8 metas dos pilares cumpridas.** A que ficou parcial: "classe nova toca
  no máximo 2 arquivos" (vale para variações; não para comportamento novo).
- **Qualidade no fim:** 124 testes da lógica, cobertura 100%, nenhum mutante
  sobrevivente (161 mortos), 0 números de balanceamento no código, maior
  complexidade 7 na lógica e 9 no código de tela.
- **O gargalo de desempenho é o desenho, não a simulação:** com 1.000 inimigos na tela o jogo ainda roda a 60 FPS; a simulação aguenta 50 mil inimigos em 0,12 ms por passo. Um ECS completo não faria falta.

## Números finais

### Por fase

| Fase | Tempo (estimado) | API de Zig de outra versão | Testes da lógica no fim |
|---|---|---|---|
| 0. Setup (devbox e esqueleto) | ~20 min | 0 | 6 |
| Ferramentas de qualidade (`zig build quality`) | ~30 min | 2 | 6 (+25 das ferramentas) |
| 1. Fila | ~25 min | 0 | 34 |
| 2. Inimigos e combate | ~35 min | 2 | 83 |
| Guia visual, brilho e camadas | ~40 min | 0 | 83 |
| 3. Dados e classes | ~30 min | 0 | 111 |
| 4. Ondas e fim de jogo | ~30 min | 0 | 124 |
| 5. Medições e retrospectiva | ~35 min | 1 (num script descartável) | 124 |
| **Total** | **~4h** | **5** | **124** (+30 das ferramentas, +1 dos dados) |

Os tempos são estimativas pelos horários da sessão (pushes, execuções do CI);
contam o trabalho do Claude, não a leitura e a revisão. Ficaram de fora dois
incidentes de ambiente (WSL sem memória e disco cheio, ~25 min).

### Qualidade (`zig build quality`, fim da fase 4)

| Medição | Valor |
|---|---|
| Cobertura de linhas (lógica) | 🟢 100% (584/584) |
| Mutação | ✅ 161 mortos, 0 sobreviventes, 79 não compilaram, 1 por tempo, 3 desativados com motivo |
| Números de balanceamento em `src/` | 🟢 0 (2 liberados com motivo: o `2` de `@Vector(2, f32)` e a tolerância dos testes) |
| Maior complexidade | 🟢 7 na lógica (`events.write`, um `switch` sobre todos os eventos); 🟢 9 no código de tela (`main`, com o desvio do `--bench`) |
| Imports entre sistemas / ciclos | ✅ 0 / nenhum |
| Commits `fix:` com teste | 🟢 2/2 |
| Determinismo (mesma seed, mesmo hash) | ✅ |

### Bugs

- **Pegos pelos testes:** 2 no jogo (`pointAt` com NaN em segmento de
  comprimento 0; `hash()` lendo o lixo do preenchimento do `@Vector`) e os
  sobreviventes da mutação, que eram testes faltando ou código redundante.
- **Só apareceram rodando o jogo:** 1 (`integer overflow` no overlay de debug,
  `@min` com constante devolvendo `u5`). Código de tela não tem teste de
  unidade.
- **Do ambiente, não do jogo:** um mutante que alocava em laço derrubou o WSL
  por falta de memória; o cache dos mutantes encheu 18 GB de disco. Os dois
  viraram limites no `mutate` (memória, tempo e cache próprio).

## Os 3 pilares

| Pilar | Meta | Resultado |
|---|---|---|
| Modular | 0 imports entre sistemas | ✅ medido pelo `analyze` |
| Modular | Lógica testável sem janela | ✅ `zig build test-headless` não linka a raylib |
| Modular | Classe nova toca no máximo 2 arquivos | ⚠️ parcial: 1 arquivo para variação de classe; 7 para o mago |
| Editável | 0 números de balanceamento em `src/` | ✅ medido pela AST e revisado à mão |
| Editável | Ondas vindas de dados | ✅ `data/waves.zon`, lido ao abrir o jogo |
| Depurável | Overlay de debug (F1) | ✅ FPS, entidades, relações e eventos do frame |
| Depurável | Seed fixa | ✅ teste de determinismo de 20 s de jogo |
| Depurável | Todo bug corrigido ganha teste | ✅ 2/2 commits `fix:` |

**Por que o mago tocou 7 arquivos:** ele trouxe ataque novo (área) e acessório
novo (chapéu). Em Zig, sem registro dinâmico de sistemas, um sistema novo
precisa ser chamado no `sim.zig` e exposto no `game.zig` (para os testes
rodarem), além do próprio arquivo, da variante no `classes.Attack`, dos dados,
do exemplo dos testes e do desenho. Um "besteiro" (mais alcance, menos
cadência) é só uma entrada no `classes.zon`. O pilar acerta para o caso comum
(variações) e erra para o caso caro (comportamento novo).

## As ideias de "O essencial" na prática

| Ideia | Como ficou | Valeu? |
|---|---|---|
| Dados em arquivo | `game.zon`, `classes.zon`, `waves.zon`, lidos em tempo de execução e conferidos juntos por `data/check.zig` | Sim. Dificuldade, classes e ondas mudam sem recompilar, e referências erradas (classe que não existe) reprovam no teste |
| Eventos como objetos | Fila `ArrayList(Event)` processada por passo; `switch` exaustivo no `describe` | Sim. Nenhum sistema importa outro; o overlay mostra cada evento de graça; o compilador obriga a tratar evento novo |
| Variáveis observáveis | **Testado se fazem falta:** a UI lê o `World` direto, a cada frame | Não fizeram falta no MVP. Com o estado inteiro num lugar só e a tela redesenhada todo frame, observar mudanças não traz nada |
| Id com generation | `Pool(T)` com `index` + `generation` | Sim. Evento ou relação com handle velho é ignorado em vez de acertar o inimigo novo da mesma vaga (tem teste) |
| Separar dados de lógica | Sistemas são funções sobre o `World`, um por arquivo | Sim. Teste de sistema monta o estado direto no `World`, sem janela |
| Composição | Classe = tagged union de ataque + aparência, guardada por índice | Sim para variações; comportamento novo ainda pede código (ver o mago) |
| Relacionamentos com curinga | `(Segue, líder)`, `(Mira, inimigo)`, `query(.mira, .any)` | Sim, e pequeno (~100 linhas). Separou "escolher alvo" de "atirar" |
| Encapsulamento | `health.zig`: a vida só muda pelas funções do módulo | Por convenção: o Zig não tem campos privados |

## Comparação com a série (ROG)

As versões do ROG são em C# e Unity e seguem um tutorial (armas, pickups);
o QuackAttack é em Zig, com outro jogo. A comparação vale pelas tendências,
não pelos números exatos. As métricas de código foram medidas com o **mesmo
script** nos quatro códigos (regex, não AST), só nos scripts próprios de cada
um (sem o framework SOAP nem o TextMesh Pro).

### Critérios dos posts da série

| Critério | Spaghetti | ECS | SOAP | QuackAttack |
|---|---|---|---|---|
| Tempo | 5h36 (5 partes); 53 min na parte 1 | 4h24 e abandonada na parte 2 | 3h05 (4 partes) | ~4h, com MVP completo, testes, ferramentas de medição e esta retrospectiva |
| Debug | Direto, mas com acoplamento indesejado | Sem integração com o Inspector | "Muito mais controlado e intuitivo" | Overlay F1 com eventos e relações; seed fixa reproduz qualquer partida |
| Arquivos | — | "Proliferação de arquivos" | — | Muitos arquivos pequenos (um sistema por arquivo), sem atrapalhar |
| Carga mental | — | Alta (fora da POO) | Baixa | Baixa para o desenvolvedor: as regras ficaram no `CLAUDE.md` e no CI, não na cabeça |

O tempo do QuackAttack é trabalho do Claude Code com os seus prompts, não
horas de um desenvolvedor sozinho: compare com cuidado.

### Métricas de código (mesmo script nos quatro)

| Métrica | Spaghetti | SOAP | ECS | QuackAttack (tudo) | QuackAttack (lógica) |
|---|---|---|---|---|---|
| Arquivos | 16 | 12 | 21 | 33 | 25 |
| Linhas de produção | 448 | 266 | 340 | 1.565 | 1.029 |
| Linhas de teste | 0 | 0 | 0 | 1.225 | 1.225 |
| Testes | 0 | 0 | 0 | 124 | 124 |
| Números soltos por 100 linhas | 4,5 | 2,6 | 1,5 | 6,5 | 0,2 |
| Complexidade média / máxima | 2,0 / 6 | 1,4 / 4 | 1,5 / 5 | 2,4 / 7 | 2,5 / 7 |
| Acoplamento (arquivos referenciados): mediana / máximo | 1 / 5 | 0,5 / 2 | 2 / 4 | 3 / 24 | 3 / 24 |

Como ler:

- **Números soltos:** a lógica do QuackAttack é a mais limpa (0,2, e os únicos
  dois são liberados com motivo), mas o código de tela tem muitos números de
  layout (tamanhos, cores, frações do raio). Na Unity, esses valores ficam no
  Inspector e nas cenas, fora do código.
- **Acoplamento:** a mediana mais alta vem de cada sistema importar `world`,
  `vec`, `pool` e `testing`, que são dados e utilitários, nunca outro sistema.
  O máximo de 24 é o `game.zig`, que só reexporta os módulos para os testes. O
  SOAP continua o menos acoplado: lá a comunicação passa por ScriptableObjects
  que nem aparecem como referência no código.
- **Tamanho:** o QuackAttack é maior porque faz mais (MVP completo, desenho
  por primitivas em código, testes). Por linha de produção, a complexidade é
  parecida com a do Spaghetti; a diferença está nos testes e nas regras
  medidas no CI.

## O ECS completo faria falta?

O `PLANO.md` pedia "quantas entidades na tela antes de o FPS cair (para
saber se o ECS completo faria falta)". Duas medidas, em build otimizada
(`ReleaseSafe`), numa RTX 2060:

**Jogo inteiro** (`quackattack.exe --bench`, Windows nativo): a cada 2 s
entram 250 inimigos que não morrem (os patinhos continuam atirando neles),
com o FPS destravado.

| Inimigos na tela | Simulação | Frame inteiro | FPS |
|---|---|---|---|
| 0 | 0,001 ms | 0,6 ms | 1.555 |
| 500 | 0,005 ms | 8,7 ms | 114 |
| 750 | 0,006 ms | 12,4 ms | 80 |
| 1.000 | 0,007 ms | 16,2 ms | **62** |
| 1.250 | 0,008 ms | 19,9 ms | 50 |

**Só a simulação**, sem janela:

| Inimigos | Tempo por passo |
|---|---|
| 1.000 | 0,003 ms |
| 10.000 | 0,026 ms |
| 50.000 | 0,123 ms |

**Resposta: não faria falta.** A simulação, com os dados já separados por
campo (`MultiArrayList`, `Pool`), gasta menos de 1% do frame mesmo com 50 mil
inimigos. O limite de ~1.000 inimigos na tela vem do **desenho**: cada inimigo
são umas 8 formas primitivas (círculos de 36 segmentos, retângulo arredondado,
elipse), desenhadas uma a uma. O MVP chega a 30 inimigos por onda: há folga de
30 vezes. O limite está no desenho, não na arquitetura.

Pelo WSL (OpenGL traduzido para D3D12 pelo WSLg), o mesmo jogo cai abaixo de
60 FPS já com 250 inimigos: medir desempenho de desenho precisa ser no
executável nativo.

## Claude Code com Zig

- **5 vezes** o Claude escreveu API de outra versão do Zig (`@enumFromInt`,
  `b.pathFromRoot`, repetição de array com `**`, `std.fmt.bufPrintZ` e, num
  script descartável de medição, `std.time.Timer`). Todas
  pegas pelo compilador ou pelo `zig fmt` na hora; as do projeto viraram linha
  no `CLAUDE.md`. Outras 4 foram evitadas conferindo a std local antes de
  escrever.
- **O que mais ajudou:** a versão fixa no `build.zig.zon` e no devbox; a
  regra "confira na fonte local da std" no `CLAUDE.md`; e o `zig build test`
  + `quality` como portão de cada tarefa.
- **Armadilhas do Zig que viraram regra:** o preenchimento com lixo de
  `@Vector` e de unions (o tamanho do vetor muda com o backend), o `@min` que
  devolve inteiro estreito, e o Zig só compilar o que é usado (o que escondia
  funções da cobertura).
- **A mutação foi a ferramenta que mais mudou o código:** achou testes
  fracos, helpers de teste tratados como produção, mutantes equivalentes e,
  na fase 4, só código redundante. Custo: o `quality` foi de segundos para
  ~4 min (7 no CI) com 161 mutantes.
