# Guia visual do QuackAttack

Regras para tudo o que aparece na tela. Todo item novo (unidade, inimigo,
projétil, ícone, texto) segue este guia. As cores ficam em `src/ui/palette.zig`;
nada de cor solta no código de desenho.

## Princípios

1. **Leitura em meio segundo.** No meio da confusão, o jogador precisa achar a
   líder, a fila e o perigo sem procurar. Silhueta e cor vêm antes de detalhe.
2. **Chão apagado, personagens vivos.** O fundo é escuro e de pouco contraste;
   tudo o que importa é saturado e claro.
3. **Formas gordinhas e simpáticas.** Cantos arredondados, proporções
   atarracadas, carinhas com dois pontos de olho. Nada de traço fino.
4. **Pixel grande.** A cena é desenhada em resolução baixa e ampliada sem
   suavizar, para todo pixel ficar visível e nítido.
5. **Tudo o que importa brilha.** Personagens, inimigos, tiros e HUD têm uma
   auréola suave da própria cor; o chão nunca brilha.
6. **Só formas simples.** Tudo é desenhado com primitivas (círculo, elipse,
   retângulo arredondado, triângulo, linha). Sem sprites por enquanto.

## Tela e escala

- A cena é desenhada numa textura com **metade da resolução** da janela
  (`pixel_scale = 2` em `src/ui/scene.zig`) e ampliada com filtro `point`.
- As coordenadas do mundo continuam em unidades do jogo; a câmera faz a escala.
- **Unidades gordinhas:** nenhuma unidade com raio menor que 14 unidades do
  mundo (14 pixels na janela). A líder é a maior da fila.
- Tamanhos de traço e de detalhe ficam em múltiplos de 2 unidades do mundo
  (1 pixel da cena), para não aparecer meio pixel borrado.

## Brilho

- A imagem é montada em **três camadas, nesta ordem**:
  1. **fundo**: chão e sombras;
  2. **brilho**: auréola calculada só a partir dos atores;
  3. **atores**: personagens, inimigos, tiros e HUD, nítidos por cima.
  O brilho fica **embaixo** de quem o produz: nunca cobre nem borra um
  contorno. Ninguém desenha brilho à mão (`src/ui/glow.zig` e `src/ui/render.zig`).
- Tudo o que é ator vai para a camada dos atores (`scene.drawActors` ou o
  HUD); só chão e sombras vão para o fundo.
- **Quem brilha é decidido pela cor:** o que tem o canal mais forte acima do
  limite (`threshold`, 0,45) brilha; o resto não. Por isso:
  - chão, sombras, `ink` e `bar_back` ficam **abaixo** do limite (escuros);
  - personagens, inimigos, tiros e texto ficam **acima** (claros e saturados).
- Como o brilho fica embaixo, as carinhas, as cores e o pixel nítido continuam
  intactos. Se a auréola de um item novo ficar forte demais, ajuste a cor dele,
  não o brilho global.
- O overlay de debug (F1) é desenhado depois e não brilha.

## Chão

- Xadrez de **dois tons de grafite** muito próximos (`floor_a`, `floor_b`),
  casas de 32 unidades. O xadrez dá noção de movimento sem chamar atenção.
- Nada de detalhe no chão que possa ser confundido com uma unidade.
- O chão precisa ficar abaixo do limite do brilho: nunca clareie as casas.

## Sombras

- **Toda unidade tem sombra:** uma elipse preta translúcida (`shadow`) sob o
  corpo, mais larga que alta, levemente para baixo. É ela que "assenta" a
  unidade no chão.
- Projéteis não têm sombra (são rápidos e pequenos).

## Patos (a fila)

- **Corpo:** círculo. Filhotes amarelos (`duckling`); a líder é maior e
  branca (`leader`), para ser achada de imediato.
- **Bico:** triângulo laranja (`beak`) apontando para onde o pato vai. Cada
  filhote olha para o pato da frente.
- **Olho:** um ponto escuro (`ink`), do lado do bico.
- **Classe = acessório na cabeça**, sempre com cor própria e forma simples:
  - arqueiro: capuz pontudo verde (`archer`), `hat = .hood`;
  - mago: chapéu de mago azul (`mage`), mais alto e com aba, `hat = .pointed`.
  O acessório e a cor vêm do `data/classes.zon` (`look`); a interface só
  traduz `accent` para a cor da paleta.
  Classe nova ganha um acessório novo, de silhueta diferente das outras.
- **Invulnerável:** a fila inteira pisca (fica translúcida em intervalos).

## Inimigos

- **Corpo:** "gota" arredondada (retângulo bem arredondado, mais largo que
  alto), com **carinha**: dois olhos (`ink`) e um brilho claro no alto.
- **Cor:** coral saturado (`enemy_coral`), bem diferente das cores dos
  patos.
- **Barra de vida** logo abaixo do corpo, sempre visível: fundo escuro
  (`bar_back`) com o preenchimento proporcional à vida (`bar_fill`).
- Inimigos são sempre mais saturados que o chão e nunca brancos ou amarelos
  (essas cores são dos patos).

## Projéteis

- **Flecha:** traço curto e grosso branco (`arrow`) com ponta em triângulo,
  alinhada com a direção do voo.
- **Ataque em área:** logo depois do lançamento, um disco translúcido e um
  anel na cor da classe mostram o raio, e somem em ~0,35 s. Fica na camada dos
  atores (brilha).

## HUD

- **Coluna no canto superior esquerdo:** um ícone simples à esquerda e o
  número à direita, uma linha por informação.
- **Texto:** fonte padrão em pixel, tamanho 10 na cena (20 na janela),
  branco (`text`) com **contorno escuro** (`ink`) de 1 pixel, para ler sobre
  qualquer coisa.
- **Ícones:** desenhados com primitivas, na cor do que representam (vida =
  coração `life`).
- Informações novas entram na mesma coluna, com o mesmo padrão.

## Overlay de debug (F1)

- Painel escuro translúcido (`panel`) desenhado por cima da cena ampliada,
  em resolução cheia, com texto pequeno. É ferramenta, não parte da arte:
  pode ser mais denso que o HUD.

## Paleta

| Nome | Hex | Uso |
|---|---|---|
| `floor_a` | `#26262B` | casas escuras do chão |
| `floor_b` | `#2D2D33` | casas claras do chão |
| `shadow` | `#000000` a 55% | sombras |
| `ink` | `#16161A` | olhos, contorno do texto, detalhes escuros |
| `leader` | `#FFF4DC` | corpo da líder |
| `duckling` | `#FFD447` | corpo dos filhotes |
| `beak` | `#FF8A3D` | bicos |
| `archer` | `#3ECF8E` | capuz do arqueiro |
| `mage` | `#5B8CFF` | chapéu e feitiço do mago |
| `enemy_coral` | `#FF4F78` | inimigo básico |
| `highlight` | `#FFFFFF` a 45% | brilho nos corpos |
| `bar_back` | `#16161A` | fundo das barras de vida |
| `bar_fill` | `#FF3D5E` | preenchimento das barras de vida |
| `arrow` | `#F5F5F5` | flechas |
| `life` | `#FF4D6D` | ícone de vida |
| `text` | `#FFFFFF` | texto do HUD |
| `panel` | `#000000` a 65% | painel do overlay de debug |

## Checklist para um item novo

- [ ] Tem silhueta própria e lê bem sobre o chão escuro?
- [ ] Usa só cores da paleta (e, se precisou de cor nova, ela entrou aqui e em `palette.zig`)?
- [ ] Unidade: tem sombra? Inimigo: tem carinha e barra de vida?
- [ ] Classe de pato: tem acessório de forma e cor próprias?
- [ ] Informação no HUD: ícone + número na coluna da esquerda, texto com contorno?
- [ ] Detalhes em múltiplos de 2 unidades do mundo?
- [ ] Brilha (cor clara) se for importante, e não brilha (cor escura) se for fundo?
