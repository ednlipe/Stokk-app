# STOKK — App (front-end, login e módulos)

> Camada de dados, autenticação, abas do app e leitura de etiquetas (`stokk-vite/src/App.jsx`).
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 5. Camada de dados no front-end

- **Adaptador** `createSupabaseDB()` (em `App.jsx` e no site desktop) imita uma API de documentos:
  `db.collection(t).doc(id).set/update/get/delete` e `db.collection(t).orderBy(f,dir).limit(n).onSnapshot(cb)`.
- **Conversão de nomes:** o app usa `camelCase`; o banco usa `snake_case` (`camelToSnake`/`snakeToCamel`, só no primeiro nível).
  Por isso o conteúdo de colunas jsonb mantém as chaves como foram gravadas (ex.: `resultado.consumidoKg`).
- **Tempo real:** cada coleção assinada abre um canal `postgres_changes` e relê a tabela inteira a cada evento (`refetch`).
  O botão **Atualizar** do dashboard força `db.refetchAll()`.
- **Leitura com limite e casos antigos (v1.5.4):** quando uma leitura com `.limit(n)` volta cheia, `completarAntigos` (no adaptador,
  cópia idêntica no desktop) busca à parte o que ainda vale e ficou de fora: em `ocorrencias`, as em aberto (`liberada_em is null`,
  não anuladas); em `equipamento_locais`, o último local válido de cada equipamento que não apareceu na leitura. Sem isso, uma
  manutenção aberta há muito tempo apareceria como "Operando". Só roda quando o limite é atingido; teste em `tests/completar_antigos.test.cjs`.
- **Chave primária por coleção:** `PK = { volumes:'lote', produtos:'codigo', movimentos:'id', sessoes:'id' }`; as demais usam `id`.
- **Estado global:** objeto `state` (volumes e produtos em `Map`, listas de movimentos, sessões e produções, view atual, usuário, filtros).
- **Escritas de produção** passam por uma fila (`state.producaoFila`) para que uma gravação atrasada não sobrescreva outra.

---

## 6. Autenticação e perfis

- Login por e-mail e senha (Supabase Auth). Usuários são criados no painel do Supabase
  (*Authentication → Users*, marcando **Auto Confirm User**).
- Todo login novo vira `operador` **bloqueado** (`ativo = false`). Para liberar: *Table Editor → profiles → ativo = true*; para virar supervisor, `role = 'supervisor'`. Conta bloqueada vê "Conta aguardando liberação" e não carrega dados (app e desktop, em `onAuthed`). Desligar "Allow new users to sign up" no Supabase.
- A interface esconde elementos marcados com `data-role="supervisor"` para operadores (`applyRoleUI`). A **autorização real** é feita pelas políticas RLS do banco.
- A topbar mostra `nome · perfil · v<APP_VERSAO>`. `APP_VERSAO` = versão do `package.json` + carimbo automático da build (vite `define`: `__APP_VERSION__`, `__APP_BUILD__`); aparece também na tela de login. No site desktop é uma constante em `index.html`. A cada release subir `package.json` e `versionCode`/`versionName` em `android/app/build.gradle`.

**Supervisor:** importar planilha, excluir volumes (seleção em lote), excluir conferências, baixar não localizados, ver Histórico, cadastrar/atualizar produtos, **excluir registro de produção finalizado** (relatório › 'excluir este registro de produção'; só apaga o registro, não mexe no estoque).

**Push (somente APK):** `registrarPush()` pede permissão `POST_NOTIFICATIONS`, registra o token via `rpc registrar_push_token` e, ao tocar na notificação, abre Conferência. O aviso de conferência aberta é enviado às 8h, 12h e 15h (Brasília) pela Edge Function `avisar-conferencias` (ver `deploy.md`). **Status:** não testado em produção.
**Operador:** bipar, consultar estoque, conferir, registrar produção, ver dashboards.

---

## 7. Módulos do app (abas)

Barra inferior do app: **Início · Bipar · Estoque · Conferência · Produção · Mais** (o botão "Mais" abre a tela **Importar** e só aparece para supervisor).
A tela **Histórico** existe no código, mas **não tem botão no menu do app** (hoje só é acessível no site desktop — ver limitações).

### 7.1 Início (dashboard de estoque)
Cartões e gráficos sobre os volumes com `status = 'estoque'`: produtos em estoque (rosca), visão geral/comparativo por armazém,
histórico recente, status do estoque, consumo interno (armazém 92), "OK para carregar (93) × concessão (97) × retrabalho (98)",
quebra por armazém, e insights. Botão **Atualizar**.

### 7.2 Bipar
- Dois modos de leitura (lembrados no aparelho): **Coletor** (leitor USB/Bluetooth em modo teclado, campo sempre focado e sem teclado do celular) e **Câmera** (`BarcodeDetector`).
- Fallback por **foto/OCR**: lê o texto impresso (Código/Volume/Corrida/Peso) e remonta o código.
- Ao bipar: vibra e toca bipe (OK/erro), mostra aviso grande e o resultado do volume.
- **Ação em lote** ("Status ao bipar"): Bloquear, Transferir, texto livre etc.; fica valendo até trocar. Cada bipe grava movimento e muda o status.
- Se há conferência ativa, o bipe marca o volume como **contado**.
- Etiqueta não cadastrada: abre **cadastro manual** pré-preenchido pelo parser (o operador sempre confere antes de salvar).

### 7.3 Estoque
Lista de volumes com busca, filtros múltiplos (status e armazém), badges de situação, detalhe do volume, **troca de armazém**,
e (supervisor) **seleção e exclusão em lote**. Exporta o relatório de inventário em Excel.

### 7.4 Conferência (inventário)
> **Contagem cega (v1.4.0):** ao tocar em "Iniciar conferência" abre um popup para escolher **Padrão** ou **Cega** (o nome opcional da cega vem do campo de nome da tela); a tela também lista as contagens cegas em andamento e anteriores. A bipagem usa a mesma tela Bipar (`scanOverride = cegaBipar`, como na Produção) e a lista fica em `#view-cega-lista`. Regras em `regras-de-negocio.md` §9.3.1. **Status:** testado em navegador com API simulada; falta testar com coletor/celular reais e com a planilha do mesmo produto das etiquetas.
Fluxo detalhado na [seção 9.3](#93-conferência-de-inventário).

### 7.5 Produção (rendimento metálico)
Dois modos: **Registrar** e **Dashboard**.

**Registrar:** equipamento (`LAM02/LAM03/RT200`) → turno → data do turno → *Iniciar registro*;
bipa/digita a **matéria-prima** consumida → *Finalizar matéria-prima* → informa o **código do produto gerado**
→ bipa/digita os **produtos** → *Finalizar produção*.
Na finalização (`producaoConcluirInterno`):
1. rolos consumidos viram `status = baixado` e geram movimento `baixado` ("Consumido na produção X");
2. produtos gerados entram no estoque já como `contado` (`origem = producao`) e geram movimento `entrada` ("Produzido em X"); se o lote não existe, é criado (o produto só é vinculado se existir em `produtos`);
3. por último a produção é fechada com `resultado`. Se algo falhar nos passos 1–2, a produção **continua aberta** e pode-se tentar de novo (idempotente: não duplica movimentos já gravados).

Outros recursos: retomada de produção em andamento (por usuário, em `localStorage`), digitação manual de rolo, remoção de item, exportação da produção.

**Dashboard:** matriz mês × dia × turno por equipamento, regras na [seção 9.4](#94-rendimento-metálico).

### 7.6 Importar (supervisor)
Aceita um ou mais `.xlsx` do relatório do Protheus. Um arquivo pode ter vários blocos "Produto:".
Para cada produto: grava em `produtos` e faz *upsert* dos volumes (8 em paralelo). **Toda importação marca os volumes como `nao_conferido`**
(é um retrato do ERP ainda não confirmado fisicamente). Registra um movimento `importacao`.

### 7.7 Histórico
Lista dos movimentos (até 200 na tela, 300 carregados) com filtro por tipo e exportação Excel. No app React a tela não tem entrada no menu; no site desktop ela está no menu lateral (supervisor).

---

### 7.8 Gestão · Diesel (ambiente `gestao`, v1.5.0)
Aparece só para quem tem a área **Gestão** (`usuario_areas`). Nessa área o menu de baixo troca para **Resumo · Abastecer · Tanque · Equipamentos** (`esconderAbasPorArea`, `ABAS_GESTAO`); as outras áreas não veem essas abas. Telas `#view-gdash`, `#view-gabast`, `#view-gtanque`, `#view-gequip`; em `subscribeData` a área Gestão assina só as 5 tabelas do diesel (`subscribeDiesel`). Regras de cálculo: `regras-de-negocio.md` §9.5; tabelas: `banco.md` §4.3.1.
- **Resumo:** saldo, custo médio e "dura cerca de N dias" por tanque; equipamentos sem abastecer; litros/abastecimentos/gasto/custo médio do mês; últimos abastecimentos; exportar (supervisor).
- **Abastecer:** equipamento, tanque, horímetro ou km (o rótulo muda), litros, data/hora, "troca de medidor", observação. Mostra o último valor, o consumo desde o último (L/h ou km/L) comparado com a média, e o custo estimado. Bloqueia medidor menor que o anterior; pergunta antes de registrar se o medidor andou demais ou se os litros passam do saldo do tanque. Histórico com filtro; supervisor **anula** (com motivo).
- **Tanque:** saldo, capacidade, mínimo, entradas/saídas. Supervisor: nova compra (preço por litro **ou** valor total), conferir com a régua, novo/editar tanque, anular, exportar compras.
- **Equipamentos:** lista com último abastecimento e consumo médio; toque abre o detalhe (30 dias, gasto, últimos abastecimentos). Supervisor: cadastrar/editar (código, nome, tipo, unidade h/km, áreas de uso, aviso após N dias, só dias úteis, aviso ligado/desligado, ativo). A unidade não muda depois que há abastecimento.
- **Gravação:** as tabelas do diesel só aceitam INSERT (sem "upsert", que exigiria UPDATE em todas as colunas); correção = anular e lançar de novo. Se o `update_015` não foi rodado, as telas mostram o aviso em vez de erros.
- Funções (prefixo `dsl`/`gabast`/`g`): núcleo `dslTanque`, `dslConsumo`, `dslSemAbastecer`, `dslResumo`…; telas `renderGDash`, `gabastMontar`/`gabastRegistrar`, `renderGTanque`, `renderGEquip`, `gCompraSheet`, `gReguaSheet`, `gTanqueForm`, `gEquipForm`, `gAnularSheet`.
- **Status:** testado no navegador com Supabase simulado e nos testes automáticos; **não testado em produção nem no APK**.

### 7.9 Gestão · Paradas e manutenção (v1.5.1)
Quinta aba da Gestão (**Paradas**, `#view-gmanut`, `ABAS_GESTAO` inclui `gmanut`). Regras: `regras-de-negocio.md` §9.6; tabela: `banco.md` §4.3.2.
- **Em aberto:** cartões vermelhos com equipamento, categoria, motivo, descrição, quem abriu e há quanto tempo está parado. Supervisor vê **Liberar equipamento**; os demais veem "Quem libera é o supervisor".
- **+ Abrir ocorrência:** equipamento (só os que não têm ocorrência aberta), *Manutenção* ou *Parada*, motivo (a lista muda com a categoria; `MANUT_MOTIVOS`), descrição e data/hora. Salva e avisa os supervisores (`gManutAvisar`, chama a Edge Function tipo `ocorrencia`; se falhar, só registra no console).
- **Liberar (supervisor):** por que foi liberado (`MANUT_LIBERACAO`), o que foi feito, quem pegou, data/hora (não antes da abertura nem no futuro). Depois de gravar o app confere se a liberação valeu; senão avisa que falta permissão.
- **Mês** (ocorrências, horas paradas, tempo médio), **Histórico** (liberadas e anuladas; toque abre o detalhe completo, com **Anular** para o supervisor) e **Exportar paradas (Excel)**.
- **Em outras telas:** Resumo mostra o cartão **Parados agora**; Equipamentos mostra a etiqueta "em manutenção"/"parado"; Abastecer avisa se o equipamento está com ocorrência aberta.
- Se o `update_016` não foi rodado, só esta aba mostra o aviso (`state.paradasErr`); o diesel continua funcionando.
- Funções: `renderGManut`, `gManutCard`, `gManutLinha`, `gManutAbrirSheet`, `gManutLiberarSheet`, `gManutDetalhe`, `gManutExportar`, `gManutAvisar`. Tabela assinada em `subscribeDiesel` (`ocorrencias`, por `abertaEm`).
- **Status:** testado no navegador com Supabase simulado (supervisor e operador) e nos testes automáticos; **não testado em produção, no APK nem com push real**.

### 7.10 Gestão · Locais e correção de ocorrência (v1.5.2)
Quarta aba nova da Gestão (**Locais**, `#view-glocal`; `ABAS_GESTAO` ficou com Resumo · Abastecer · Paradas · Locais · Tanque · Equipamentos). Regras: `regras-de-negocio.md` §9.7; tabela: `banco.md` §4.3.3.
- **Onde estão agora:** lista de equipamentos ativos com o local atual, observação, desde quando, há quanto tempo e quem informou; etiqueta vermelha se estiver em manutenção/parado. Busca por equipamento ou local. Tocar no equipamento abre **por onde passou** (histórico, com **anular** para o supervisor); o botão **Atualizar** abre a janela de novo local.
- **Atualizar local:** equipamento, "onde está atuando" (texto livre com sugestões dos nomes já usados), observação e "desde" (data/hora, não futura). Pergunta antes se o local é igual ao atual.
- **Últimas atualizações:** os 25 registros mais recentes (supervisor anula com motivo).
- **Em outras telas:** Equipamentos mostra "Local: …"; o cartão da ocorrência em aberto mostra o local do equipamento.
- **Corrigir ocorrência em aberto (supervisor):** botão **Corrigir** no cartão (e "Corrigir motivo / descrição" nos detalhes) altera categoria, motivo e descrição; depois de gravar o app confere se valeu.
- Se o `update_017` não foi rodado, só a aba Locais mostra o aviso (`state.locaisErr`); o resto continua funcionando (a correção de ocorrência dá o aviso de falta de permissão).
- Funções: `renderGLocal`, `gLocalLista`, `gLocalLinha`, `gLocalSheet`, `gLocalHist`, `gManutEditarSheet`, `dslLocalAtual` (núcleo). Tabela assinada em `subscribeDiesel` (`equipamento_locais`, por `dataHora`, até 5000).
- **Status:** testado no navegador com Supabase simulado (supervisor e operador) e nos testes automáticos; **não testado em produção nem no APK**.

### 7.11 Gestão Planta 1 · 5S (v1.6.0)
Ambiente novo (`state.area === 'gestao_p1'`; `ABAS_DA_AREA`/`ABA_INICIAL` generalizam o que antes era só `gestao`). Duas abas: **Resumo** (`#view-c5resumo`) e **5S** (`#view-c5lista`).
- **Resumo:** alerta de 5S em aberto há mais de 7 dias; no mês: concluídos, abertos, em aberto agora, tempo médio; por setor e por pessoa; botão **Exportar 5S (Excel)** (supervisor).
- **5S:** **+ Novo 5S** (setor, o que está errado, foto do antes, data/hora; caixa "Já resolvi" mostra foto do depois e "o que foi feito"); **Em aberto** (foto, setor, descrição, quem/quando, botão **Concluir**); **Concluídos** (antes e depois lado a lado). Tocar no item abre o detalhe com as fotos grandes; supervisor: **Corrigir setor/descrição** (só em aberto) e **Anular 5S**.
- **Foto:** `<input type=file accept=image/* capture=environment>` (câmera) ou galeria; `c5Comprimir` reduz no aparelho (1280 px, JPEG, alvo 300 KB) antes de `c5Enviar` (Storage `cinco-s`, `upsert:false`). As fotos são privadas: `c5Urls`/`c5Hidratar` pedem links temporários de 1 h (`createSignedUrls`) e preenchem as `<img data-c5>`. A permissão de câmera já está no `AndroidManifest.xml`.
- Sem internet a foto **não é enviada**: o app avisa e a janela continua aberta (a foto reduzida fica na tela) para tentar de novo; não há fila offline.
- Se o `update_018` não foi rodado, as duas abas mostram o aviso (`state.cincoErr`).
- Funções: `renderC5Resumo`, `renderC5Lista`, `c5AbrirSheet`, `c5ConcluirSheet`, `c5EditarSheet`, `c5Detalhe`, `c5Exportar`, `c5Clique`, `subscribeCinco`, `completarAntigos` (ramo `cinco_s`: traz os abertos antigos se a leitura bater no limite de 5000).
- **Status:** testado no navegador com Supabase simulado (supervisor e operador: abrir, concluir, abrir e concluir, corrigir, anular, foto de 7,8 MB reduzida para ~90 KB) e o SQL em Postgres local; **não testado** com o Supabase real, com câmera real no APK nem com fotos reais de celular.

## 8. Leitura de etiquetas e leitores

### 8.1 Formato da etiqueta
Código de barras lateral, sem separadores: **Volume (8) + Corrida (6) + Peso em kg (4 dígitos) + Código do produto (resto)**.
Exemplo: `PCI00047PCI0032173TPAIQ092B4` → volume `PCI00047`, corrida `PCI003`, peso `2173 kg`, produto `TPAIQ092B4`.
Tem ~25–30 caracteres, por isso exige leitor com **faixa de leitura larga**.

### 8.2 Parsers
| Função | Papel |
|---|---|
| `extractLoteCode` | remove tudo que não é letra/número, procura o lote no cadastro ou casa `[A-Z]{2,6}\d{4,7}` |
| `parseEtiquetaCodigo` | separa volume/corrida/peso/produto (exige > 18 caracteres, volume `[A-Z]{2,3}\d{4,6}`, peso com 4 dígitos) |
| `encontrarProdutoPorCodigoEtiqueta` | aceita código curto (`TPAIQ092B4`) quando só um produto do cadastro começa com ele (`TPAIQ092B4.20`) |
| `parseEtiquetaOCR` / `reconstruirCodigoEtiquetaOCR` | leitura por foto (Tesseract.js, idioma `eng`) |

### 8.3 Hardware
- Leitor recomendado (pendente de compra/validação): **laser 1D USB em modo teclado (HID)**, com boa distância de leitura.
  Candidato: Bright LB001. Pendente: medir a largura total do código e a barra mais fina da etiqueta real.
- No celular, leitor USB precisa de adaptador **OTG** (USB → USB-C); leitores Bluetooth funcionam em modo HID.
- **A verificar:** texto real lido pelo leitor para etiquetas `MB…` e `BCJ…` (o parser foi escrito para o padrão `PCI…`).

---

**Áreas (v1.3.0, 20/10):** no login, `onAuthed()` lê `profiles.area` e a linha de `areas`; conta sem área ou com área desativada é deslogada com aviso ("sua conta ainda não tem uma área" / "você não tem permissão para acessar esta área"). A área aparece na barra do topo (`state.user.areaNome`). O app não envia `area` nos registros: o banco usa `area_padrao()`. Mesma lógica no site desktop. **Status:** compilado (build ok); não testado em campo. Se `profiles.area` for `undefined` (banco sem `update_012`), o app funciona como antes.
**Várias áreas (v1.3.0, 20/10):** `onAuthed()` junta `profiles.area` + `usuario_areas`. Uma área → entra direto; duas ou mais → tela `#area-picker` após o login (com "Sair"); a escolha fica em `localStorage` `stokk_area_<userId>`. Botão `#btn-area` ("trocar área") no topo abre a folha de troca; trocar salva a escolha e faz `location.reload()`. A camada de dados filtra `.eq('area', state.area)` em `volumes`, `movimentos`, `sessoes`, `producoes` e grava `row.area`; `produtos` é compartilhado. Sem `state.area` (banco sem update_012) não filtra. Nome da área aparece na barra do topo. Igual no site desktop. **Status:** testado com Supabase simulado no navegador; falta testar no celular/produção.
**Abas por área (21/10):** na Planta 1 a aba Produção (app) / Rendimento (desktop) fica escondida, pois a laminação ainda não tem rendimento definido. Controlado por `ABAS_OCULTAS_POR_AREA` e `esconderAbasPorArea()` (chamada em `onAuthed`). É só visual: o banco ainda aceita produção na Planta 1. Para voltar, tire `planta1` da constante. **Status:** testado só no navegador com API simulada.
