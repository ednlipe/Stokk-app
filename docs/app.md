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
- **Várias fotos (v1.6.1):** os campos "Foto do ANTES" e "Foto do DEPOIS" aceitam até 5 fotos cada (`C5_MAX_FOTOS`): câmera uma por vez, ou várias da galeria de uma vez (`multiple`); cada foto aparece em miniatura com ✕ para tirar e o tamanho em KB; ao chegar em 5 os botões somem. O envio é sequencial ("Enviando foto 2 de 5…", `c5EnviarVarias`) e cada arquivo tem nome único, então repetir depois de uma falha não esbarra nas fotos já enviadas (sobram arquivos órfãos, sem efeito). Com uma foto só, o app nem envia as colunas das extras (continua funcionando mesmo antes de rodar o `update_019`). Listas mostram "N fotos" na miniatura; o detalhe mostra todas.
- **Foto:** `<input type=file accept=image/* capture=environment>` (câmera) ou galeria; `c5Comprimir` reduz no aparelho (1280 px, JPEG, alvo 300 KB) antes de `c5Enviar` (Storage `cinco-s`, `upsert:false`). As fotos são privadas: `c5Urls`/`c5Hidratar` pedem links temporários de 1 h (`createSignedUrls`) e preenchem as `<img data-c5>`. A permissão de câmera já está no `AndroidManifest.xml`.
- Sem internet a foto **não é enviada**: o app avisa e a janela continua aberta (a foto reduzida fica na tela) para tentar de novo; não há fila offline.
- Se o `update_018` não foi rodado, as duas abas mostram o aviso (`state.cincoErr`).
- Funções: `renderC5Resumo`, `renderC5Lista`, `c5AbrirSheet`, `c5ConcluirSheet`, `c5EditarSheet`, `c5Detalhe`, `c5Exportar`, `c5Clique`, `subscribeCinco`, `completarAntigos` (ramo `cinco_s`: traz os abertos antigos se a leitura bater no limite de 5000).
- **Status:** testado no navegador com Supabase simulado (supervisor e operador: abrir, concluir, abrir e concluir, corrigir, anular, foto de 7,8 MB reduzida para ~90 KB) e o SQL em Postgres local; **não testado** com o Supabase real, com câmera real no APK nem com fotos reais de celular.

### 7.12 Usuários (v1.7.0, só administrador)
Link **usuários** no topo (em qualquer área; `state.user.admin = profile.admin === true`), abre `#view-usuarios` (sem aba embaixo; "← voltar" volta para a aba inicial da área). Lista todas as contas com chips (admin, papel, bloqueado, áreas). Toque numa conta: nome, papel, áreas (caixas), **Salvar**; **Redefinir senha** (campo + "Gerar"); **Bloquear/Reativar acesso**. **+ Novo usuário:** nome, e-mail (login), senha inicial (gerada, editável), papel, áreas; ao criar mostra login e senha **uma vez** com botão copiar. Tudo via `admChamar(acao, dados)` → Edge Function `admin-usuarios` (`listar`/`criar`/`atualizar`/`senha`); erro de função não publicada vira aviso na tela. Funções: `admRender`, `admClique`, `admNovoSheet`, `admEditarSheet`, `admResultadoSheet`, `montarBotaoUsuarios`.
- **Status:** testado no navegador com a função simulada (criar, duplicado, editar, bloquear, senha, travas de si mesmo, função ausente) e a lógica da função com banco simulado; não testado no Supabase real.

### 7.13 Atualização do APK (v1.7.1, só no app Android)
Ao abrir o app (e ao voltar para ele, no máximo 1x a cada 30 min) `atuVerificar` baixa `versao.json` da Release `apk-latest` (via `CapacitorHttp`, sem CORS) e compara `codigo` com o `versionCode` instalado (plugin `Atualizador.info`). **Só se for maior** abre o popup "Nova versão disponível" (várias versões seguidas: aparece só a última, porque o `versao.json` é sempre o mais recente). **Atualizar agora:** se o Android ainda não deixou o STOKK instalar apps, abre a tela "Permitir deste app" (uma vez); depois baixa o APK com barra de progresso, o plugin confere o SHA-256 e abre o instalador do Android (a pessoa toca em **Instalar**). **Depois:** não avisa de novo até fechar o app. O app só aceita `versao.json` cujo `url` seja `https://github.com/<repo>/releases/download/…` e que traga `sha256`. No site/desktop nada disso roda (`Capacitor.isNativePlatform()`).

### 7.14 Stokkbook (v1.8.0, para todos)
Botão azul **Stokkbook** no topo (em qualquer área; selo vermelho com novidades desde a última abertura, guardado em `localStorage` `stokkbook_visto:<id>`; na 1ª vez não conta o que já existia) abre `#view-stokkbook` (sem aba embaixo; "← voltar"). Feed (até 60 posts, mais novos primeiro) dos posts das áreas que a pessoa acessa: avatar com inicial, "Fulano concluiu um 5S", setor · área · tempo relativo, problema/feito, fotos antes/depois (toque para ampliar), reações 👏 🎉 🚀 👍 (uma por pessoa; tocar na mesma tira, em outra troca) e "Você, Ana e mais 2 reagiram". Supervisor vê "ocultar post" (pede motivo) e "reexibir" nos ocultos. Atualiza em tempo real (`subscribeStokkbook`, recarrega com 0,5 s de atraso). Tela de **concluir 5S** ganhou a caixinha "Postar no Stokkbook 🎉" (marcada). Sem o `update_021` a tela avisa que o Stokkbook não foi ativado. Funções: `sbkCarregar`, `sbkRender`, `sbkCartao`, `sbkReagir`, `sbkOcultar`, `sbkClique`, `montarBotaoStokkbook`.
- **Status:** testado no navegador com Supabase simulado (reagir/trocar/tirar, ocultar/reexibir, foto grande, caixinha); não testado no Supabase real.

> **Stokkbook como ambiente (09/11, só no site):** no site o Stokkbook deixou de ser botão no topo e virou um **ambiente** na lista do seletor inicial e do "Trocar ambiente" (`ambientesLista`, id especial `__stokkbook`, não é área do banco). Escolhê-lo abre direto o feed (barra de baixo escondida, título "Stokkbook 🎉"); as novidades aparecem como **número laranja** no botão "Trocar ambiente" e no item Stokkbook da lista. No APK continua o botão azul no topo.

> **v1.10.0 — bloqueio por biometria (só APK):** ao abrir o app já logado e ao voltar de segundo plano após mais de 1 min, a tela fica bloqueada até digital/rosto ou PIN/padrão do celular. Código: bloco `BIOMETRIA` em `src/App.jsx` (`bioBloquear`, `bioAutenticar`, `bioPrecisaBloquear`). A sessão do Supabase continua guardada; a biometria só destrava a tela. Falha do plugin ou celular sem bloqueio de tela = não trava.
> **v1.9.2 — regra de troca de turno:** registro sem `Fim` termina sozinho no corte do turno onde começou (07:10 / 15:10 / 23:10); `Fim` informado é respeitado mesmo depois do corte. Nada é gravado enquanto o equipamento está parado: no turno novo aparece "Sem registro neste turno" com **Continuar** (formulário já preenchido, só grava ao salvar) e atalhos de Início; **Salvar e adicionar outro trecho** repete o equipamento com Início = Fim anterior. Relatórios e Excel passam a mostrar registros antigos sem `Fim` só até o fim do seu turno.
> **v1.9.2 — submenu Trefila:** ambiente Trefila abre o menu com **Estoque** (todas as abas menos Produção) e **Produção** (só a aba Produção/rendimento metálico). Os dois são a mesma área `trefila` (sem recarregar; módulo escolhido fica em `sessionStorage.stokk_modulo_id`). Só organização de tela, permissões iguais.

### 7.16 Locais por setor e turno (Veículos Móveis › Locais; app/APK e desktop)
Aba `glocal`. Faixa colorida do **turno atual** (1º 07:10–15:10 amarelo, 2º 15:10–23:10 laranja, 3º 23:10–07:10 azul, tons pastel como no desktop). Equipamentos agrupados por **setor** (`equipamentos.setor`: Pátio de Tarugo = pá carregadeira + caminhão (Meteor); Expedição = empilhadeiras; "Sem setor" por último). Cada linha: ponto **verde pulsando devagar** + selo "ao vivo" quando o último registro não terminou (`data_fim` vazio ou futuro); senão "Sem atividade agora · último: …". Formulário "Atualizar local" (v1.9.1): equipamento, **Local** (lista fixa: Planta 1, Planta 2, Trefila — `LOC_LOCAIS`), **Atividade** (obrigatória, sugestões das já usadas), **Solicitante** (opcional, quem pediu o serviço), **início** e **fim (opcional)**; o campo Observação saiu do formulário (registros antigos continuam mostrando). Aparecem no ao vivo ("Planta 1 · carregando tarugo", "pedido por …"), no histórico, no relatório de turno e nos Excel (`locTexto`). Exige o `update_023` (a atividade é sempre enviada); ao lançar um novo local o anterior termina no início do novo (cálculo, não gravação). Sem fim a coluna `data_fim` nem é enviada (funciona antes do `update_022`). Abaixo: **Turnos** com filtro de dia (**Hoje** / **Ontem** / **Outro dia** com calendário; `state.glDia`): mostra só os turnos que COMEÇAM naquele dia (o 3º começa 23:10 e termina no dia seguinte), só os que já começaram (`locTurnosDoDia`), cada um com a cor do turno e "N de M equip. com registro"; tocar abre o **relatório do turno**: por setor, a linha do tempo de cada equipamento (hora → hora, local, duração, quem; "já estava aqui desde…", "continuou depois", "sem registro"), montado na hora do histórico (anular corrige o relatório), com **Exportar Excel**. Setor se edita em Equipamentos (supervisor; só envia se mudou). Regras no bloco `LOC-CORE` (`locTurnoJanela`, `locSegmentos`, `locAoVivo`, `locLinhaTurno`, `locPorSetor`), testado em `tests/locais_core.test.cjs` (rodar com `TZ=America/Sao_Paulo`). **Desktop (v1.9.0):** o painel de parede ganhou os setores (título por setor), o ponto verde pulsando + selo "ao vivo", "Sem atividade · último: …", a faixa do turno atual, o bloco **Turnos** (Hoje/Ontem/Outro dia → relatório + Excel), o campo **Fim** em "Atualizar local" e o **Setor** em Equipamentos; o núcleo `LOC-CORE` do desktop é CÓPIA IDÊNTICA do app (o teste `locais_core` confere). **Pulso:** `@keyframes loc-pulso` (e `loc-respira` só com transparência quando o sistema pede "reduzir animações", para continuar visível no Windows com animações desligadas).

> **Excel "Controle de uso" (desktop, 10/11):** botão **Controle de uso (Excel)…** na aba Locais do desktop: abre uma janela para escolher **De / Até** (começa com o período da tela; qualquer intervalo, data final inclusive; avisa se não houver registros) e gera `controle_uso_equipamento_AAAA-MM-DD_a_AAAA-MM-DD.xlsx`. Gera o arquivo no formato da planilha da equipe: **uma aba por equipamento**, colunas ÁREA (Local · Atividade, maiúsculas), SOLICITANTE, SEMANA (ISO), DIA SEMANA, DATA INÍCIO, DATA TÉRMINO, HORÁRIO INÍCIO, HORÁRIO TÉRMINO (datas e horas são valores reais do Excel, dá para filtrar). Cada registro é cortado por dia e por turno (`locCortes`, `locLinhasPlanilha` no `LOC-CORE`); quem ainda está em andamento fica com término em branco; fim à meia-noite sai como 23:59. **Ficaram de fora por enquanto:** Centro de custo e as colunas de HE (hora extra) — regra ainda não definida.

### 7.17 Selo laranja de novidades nas abas de baixo (10/11; app/APK, v1.9.0)
Número laranja no ícone das abas **Abastecer, Paradas, Locais, Tanque** (Gestão) e **lista do 5S** (Gestão Planta 1): quantos registros de OUTRAS pessoas são mais novos que a última vez que a pessoa viu a aba (`navNovidades`, bloco `NAV-CORE`, `tests/nav_core.test.cjs`). Paradas conta abertura e liberação; 5S conta abertura e conclusão; anulados não contam. A aba aberta no momento conta como vista (o selo some ao abrir e não volta ao sair). Guarda a "última vista" em `localStorage` `stokk_aba_visto:<usuário>:<área>:<aba>` (por aparelho); na 1ª vez nada é novo. Atualiza a cada dado em tempo real (`renderAll` → `atualizarSelosAbas`). Não tem selo em Resumo/Equipamentos nem nas abas da Trefila (ainda).

### 7.15 Menu por ambiente (v1.9.0: site E APK; antes era teste só no site)
> **v1.9.0:** a trava "só no site" foi removida: `const MENU_NO_APK = true` + `modoSite()` (no código, o menu por ambiente e o Stokkbook como ambiente usam `modoSite()` no lugar de `!Capacitor.isNativePlatform()`; push e atualização do APK continuam só nativos). Para voltar a esconder no APK: `MENU_NO_APK = false`. **Não testado em APK real** (só no navegador); o botão azul do Stokkbook no topo do APK deixou de existir (some com a classe `web-amb`).
`GRUPOS_MENU` define ambientes com módulos; hoje só **Laminação Planta 1** = Inventário (`planta1`), 5S (`gestao_p1`), Veículos móveis (`gestao`). Para quem tem **2 ou mais** dessas áreas, no site: o seletor de área e o "trocar área" mostram um único item "Laminação Planta 1"; ao entrar abre `#view-menu` com cartões dos módulos que a pessoa tem; tocar num cartão troca a área (recarrega, como o "trocar área") e abre o módulo; o item **Menu** da barra de baixo volta ao menu (o botão de **Stokkbook** e o de **Usuários** saem do topo e viram cartão "Stokkbook" (com o selo de novidades) e o link "⚙ Administração: usuários", só admin, dentro do menu; "← voltar" dessas telas volta ao menu); o botão do topo passa a se chamar "Trocar ambiente"; o título mostra "Laminação Planta 1 › 5S". A barra de abas some enquanto o menu está aberto. **É só organização da tela:** as permissões continuam por área (`usuario_areas`). No **APK** (`Capacitor.isNativePlatform()`) nada disso aparece. Para virar definitivo: tirar a trava do APK, decidir se os módulos viram áreas com permissão própria e mudar o rótulo da área no banco.

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
