# STOKK — Limitações conhecidas e backlog

> 
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 13. Pendências do Diesel (v1.5.0 — nada disso foi testado em produção)

- **Antes de tudo:** o 1.5.0/1.5.1 ainda não foi aplicado; aplique 015, 016 e 017 juntos (ordem em `deploy.md`).
- Rodar `update_015_diesel.sql`, liberar a área Gestão em `usuario_areas`, publicar a Edge Function e criar o cron do tipo `diesel` (ordem em `deploy.md`).
- Testar no uso real: cadastro de tanque/equipamentos, compra, abastecimento (máquina e caminhão), anulação, conferência da régua, painel do desktop e o push de "sem abastecer".
- Confirmar com a empresa: quantos tanques e equipamentos; quem lança abastecimento e compra; se o horímetro do caminhão também importa; prazo de guarda dos registros; se a empresa quer cópia dos dados em outro lugar (Excel online/Power Automate, ver conversa de 01/11).
- Limite conhecido: o consumo assume que cada abastecimento enche o equipamento; abastecimento parcial distorce o L/h e o km/L daquele intervalo.
- Compra lançada com data antiga não recalcula o custo dos abastecimentos já gravados (de propósito).
- `schema_atual.sql` (foto do banco) ainda não inclui as tabelas do diesel: regenerar depois de rodar o `update_015` em produção.
- Backup: plano gratuito sem backup automático; registros de diesel/segurança merecem backup semanal manual.

## 13.1 Pendências de Paradas e manutenção (v1.5.1 — nada testado em produção)

- Rodar `update_016_paradas.sql` (depois do 015), publicar a Edge Function (tipo `ocorrencia`) e testar o aviso real no celular: abrir como operador → supervisor recebe; liberar → supervisor e quem abriu recebem.
- Confirmar com a empresa: a lista de motivos (`MANUT_MOTIVOS` e `MANUT_LIBERACAO` em `src/App.jsx`) e se o **operador/responsável** também deve poder liberar (hoje só o supervisor libera; mudar exige alterar a política `ocorrencias_update` e as colunas liberadas).
- Quem libera digita à mão "quem pegou o equipamento" (texto livre). Se quiser escolher da lista de pessoas, é uma melhoria futura.
- Se o app ficar sem internet ao abrir/liberar, a ocorrência não é gravada (o app mostra o erro); o aviso push falho não é reenviado.
- Sem foto/anexo na ocorrência e sem ligação com o checklist de segurança (ideia futura).

## 13.2 Pendências de Localização e lançamentos no desktop (v1.5.2 — nada testado em produção)

- **v1.5.3 (desktop):** testar o "Modo parede" em tela cheia na TV/monitor real (tamanho das letras, quantidade de cartões que cabem sem rolar). Se houver muitos equipamentos, avaliar rolagem automática.
- **Painel de parede (revisão do 1.5.3, ainda abertos):** não mostra quando foi a última leitura com sucesso (sem internet, a tela parece atualizada com dados velhos); sem Wake Lock (a TV pode dormir); a tela cheia se perde ao recarregar a página (falta `?parede=1`/modo quiosque); relógio e período usam o fuso do aparelho, não Brasília; o redesenho a cada 30 s reinicia a rolagem das tabelas fora do modo parede; parados ordenados por código, não por tempo parado.
- **v1.5.4:** testar com o Supabase real que o painel e o app continuam mostrando ocorrências e locais (a busca extra `completarAntigos` só entra quando a leitura atinge o limite: 3.000 ocorrências / 5.000 locais).
- **Tempo real relê a tabela inteira:** o evento do realtime chama `refetch(table)` sem o limite e a ordem da assinatura (app e desktop, `ensureChannel`). Cada abastecimento novo faz todo mundo reler a tabela `abastecimentos` inteira, e depois do primeiro evento o limite deixa de valer. Avaliar usar `fetchParams[table]` no evento (muda o comportamento de todas as áreas: testar com cuidado).
- `tests/diesel_aviso.test.cjs` precisa de **Node 22.13+** (`stripTypeScriptTypes`). Com Node 20: `npx node@22 tests/diesel_aviso.test.cjs`.

- Rodar `update_017_localizacao.sql` (depois do 016) e testar no uso real: o operador informa o local no celular, o supervisor vê no desktop e no app; correção de ocorrência em aberto; lançar abastecimento e cadastrar pelo desktop.
- **Local é texto livre:** os nomes vão variar. Se a empresa preferir uma lista fixa de locais (pátio, frente, oficina…), é uma melhoria pequena (tabela de locais cadastrados pelo supervisor).
- A localização é informada à mão e pode ficar desatualizada; o app mostra "há quanto tempo" para ajudar. Rastreio automático (celular corporativo/GPS) continua só como ideia.
- No desktop, quem lança pelo PC aparece com o nome da conta; se várias pessoas usarem o mesmo PC/login, os registros ficam no mesmo nome (cada pessoa deveria entrar com a própria conta).
- Corrigir ocorrência é só do supervisor. Se o operador também precisar corrigir a própria abertura, é mudança de política (RLS) e de coluna liberada.

## 13.3 Pendências do 5S da Gestão Planta 1 (v1.6.0 — nada testado em produção)

- **v1.6.2:** o turno do 5S usa o relógio do aparelho (como o resto do desktop), não o de Brasília; o app do celular ainda não mostra turno (só o desktop). Se precisar, levar a faixa de turno para o app.
- **v1.6.1:** rodar também `update_019_cinco_s_fotos.sql` (várias fotos) e testar com 3 a 5 fotos reais no celular (tempo de envio em rede móvel; com 10 fotos por registro o espaço sobe para ≈ 1–2 MB).
- Rodar `update_018_cinco_s.sql`, liberar `gestao_p1` em `usuario_areas` e testar no uso real: abrir com foto no celular, concluir depois, desktop (galeria e resumo), anular/corrigir como supervisor.
- **Notificação do 5S (pedido do usuário, adiada):** avisar todos da Planta 1 quando um 5S for aberto/concluído, e avisar supervisor de 5S aberto há muito tempo. Faz parte do trabalho de push, junto com o item abaixo.
- **Push no navegador/iPhone (adiado):** exige PWA (manifesto, ícone, service worker), Firebase web (config + chave VAPID, públicas) e salvar o token de cada aparelho; no iPhone só funciona com iOS 16.4+ e o site adicionado à Tela de Início.
- **Sem fila offline:** sem internet a foto não é enviada (o app avisa e deixa tentar de novo). Se a Planta 1 tiver pontos sem sinal, vale uma fila local (IndexedDB) para enviar depois.
- **Espaço:** ≈ 0,3–0,6 MB por 5S com uma foto em cada lado (até ≈ 2 MB com 5 + 5); plano grátis = 1 GB (≈ 2–3 mil registros). Acompanhar em Supabase → Storage; depois, plano pago ou arquivar fotos antigas (o app não apaga foto).
- Miniaturas: o app mostra a própria foto reduzida (~200 KB) em tamanho pequeno nas listas; se ficar pesado em rede móvel, gerar miniaturas.
- A foto pode ser da galeria (não só da câmera); a data da foto não é conferida (vale a data informada).
- `.rar`: o projeto vem de `stokk-vite.rar`; no repositório entra só a pasta (sem `node_modules`, `dist` nem `android/build`).

## 14. Limitações conhecidas

1. **Limite de 1000 linhas** por consulta do Supabase: `volumes` e `produtos` são lidos sem paginação (hoje ~200 volumes; vai quebrar ao passar de 1000). Produções são lidas com `limit(1000)`.
2. `refetch` relê a tabela inteira a cada evento de tempo real (custo cresce com o volume de dados).
3. `App.jsx` é um arquivo único de ~3,5 mil linhas com HTML em *template strings* (difícil de testar/dividir).
4. Produções finalizadas **não podem ser excluídas** pelo app (a política RLS permite ao supervisor, mas não há botão).
4b. A tela **Histórico** não tem botão no menu do app (só no site desktop).
5. O parser de etiqueta foi validado só com o padrão `PCI…`; faltam amostras reais de `MB…` e `BCJ…`.
6. Importação do Protheus é manual (planilha), sem API.
7. OCR depende de internet (Tesseract carregado do jsDelivr).
8. O site desktop não registra produções nem edita estoque além do que já faz hoje.
9. Alterações recentes estão **sem commit** no git (ver seção 3).
10. Power BI: atualização manual (ou agendada só após publicar no serviço, que exige conta corporativa).
11. `update_008` ainda **não foi aplicado em produção**: até lá vale a RLS antiga (qualquer cadastrado pode editar o próprio `role`). `powerbi_leitor` lê as views `bi` fora da RLS: manter senha forte e fora do repositório.

---

## 15. Backlog

- Rotina diária (GitHub Actions) + função `ping()` no banco para evitar a pausa do Supabase gratuito.
- Paginação de `volumes`/`produtos` (limite de 1000 linhas).
- Exclusão de produção finalizada **com reversão de estoque** (hoje só apaga o registro).
- "Pinger"/botão de restauração para o Supabase pausado.
- Impressão de etiquetas.
- Integração com a API do Protheus.
- Ajuste do parser com texto real do leitor USB (`MB…`, `BCJ…`).
- Confirmar e aplicar as 34 medidas do `medidas_stokk.json`; concluir a página "Painel" do Power BI; segunda página de estoque/conferências.
- Roteiro de apresentação para a diretoria (o app com dados reais primeiro; o Power BI como complemento).
- Aba Produção também no app com o mesmo visual do desktop (gráfico e perda por equipamento).
- Comprar/validar o leitor de código de barras de longo alcance.

---

- [ ] Unidade kg (2026-10-13): publicar app+site, gerar APK novo, rodar `update_009_unidade_kg.sql`, trocar medidas do Power BI para `quantidade_kg` (cards em kg) e conferir o volume cadastrado à mão (digitado em t?).
- [x] Importador da planilha converte t→kg ao importar (2026-10-14).
- Push (3 tipos, crons criados): testar manualmente `conferencia` e `rendimento` e conferir o primeiro disparo automático real (19/10, ~9h, esperado 200 com `"tipo":"inventario"`) (`select status_code, content from net._http_response order by created desc limit 5;`); finalizar/excluir as 2 conferências de teste; gerar e instalar o APK 1.2.1 (ícone da notificação); decidir os próximos tipos de aviso (conta nova aguardando liberação, produção esquecida, material em análise/armazém 03, volumes liberados 93, resumo do turno); rendimento conta produções por data de finalização (não por `data_producao` do turno), ajustar se necessário.
- **Áreas (v1.3.0):** publicar na ordem de `docs/deploy.md` (012 → 013 → função → site/APK); definir a área dos usuários da Planta 1 (`profiles.area` ou `usuario_areas`); cadastrar os armazéns da Planta 1 em `armazens_area`; atualizar o Power BI (colunas `area`/`area_nome`, segmentação por área); testar em campo. Limites conhecidos: `volumes.lote` único entre áreas; nível (role) único para todas as áreas; `produtos` compartilhado; importação de planilha só grava na área do usuário; definir com o gestor da Planta 1 o que muda (barras e rolos, produção/rendimento fica para depois). Planta 1: aba Produção/Rendimento escondida; definir com o gestor o rendimento da laminação (entradas, saídas, perdas, meta) antes de reabrir.
- **Contagem cega (v1.4.0):** rodar `update_014`; testar com o coletor Zebra/Bluetooth e com uma planilha do Protheus do **mesmo produto** das etiquetas (tela soldada); confirmar que o código de produto da etiqueta é o mesmo do Protheus (hoje só informativo); definir se duas pessoas contam a mesma contagem (hoje cada contagem é de um aparelho); confirmar se o relatório do Protheus usado traz sempre `UM: TL`.

- **Desktop sem as mudanças de 26/10** (reabrir conferência/contagem, status do material em lote, grupos recolhidos ao selecionar, "Não localizado" no Excel). Só o app foi atualizado. Status: não testado em produção.

- **Lacuna no histórico `movimentos` (até 27/10).** A última linha de qualquer tipo é de 09/10/2026. O `update_008_seguranca.sql` (executado em 11/10) deixou `authenticated` só com INSERT e SELECT em `movimentos`, mas o app gravava com upsert (exige UPDATE) e recebia `permission denied for table movimentos`. Corrigido em 27/10 (INSERT puro em `src/App.jsx`). Ações feitas entre ~11/10 e a correção podem ter alterado `volumes` sem deixar movimento; não recriar histórico retroativo. Conferências registradas nesse período podem ter a sessão salva mas os status dos volumes (`contado`/`nao_conferido`) não aplicados: reabrir e registrar de novo reaplica. Status: aguardando confirmação em produção.
- **v1.7.0 (Usuários):** publicar na ordem de `docs/deploy.md` (update_020 → marcar admin → função `admin-usuarios` → site/APK) e testar com uma conta de teste (criar, entrar com ela, bloquear, reativar, trocar área). Ideias futuras: versão desktop da tela; a pessoa trocar a própria senha no app; ver o registro `admin_acoes` na tela; convite por e-mail em vez de senha inicial.
- **v1.7.1 (atualização do APK):** criar os 4 segredos, desinstalar o APK antigo e instalar o primeiro assinado; conferir no Actions que o `assembleRelease` compilou o `AtualizadorPlugin.java` (não foi compilado no ambiente de desenvolvimento); testar de verdade: publicar uma versão com `versionCode` maior e ver o popup, o download e o instalador num aparelho. Ideia futura: botão "Procurar atualização" no app.
- **Excel "Controle de uso":** definir **Centro de custo** (campo no app?) e regra de **HE**; avaliar envio automático ao Excel Online (Power Automate, precisa Microsoft 365) e perfil de leitura para o coordenador.
- **v1.9.1:** conferir com a equipe se Planta 1/2/Trefila bastam (hoje não há "Outro"; mudar em `LOC_LOCAIS` nos dois arquivos via LOC-CORE) e se Atividade obrigatória / Solicitante opcional está bom.
- **v1.9.0 (pacote completo): testar em APK real** (menu por ambiente, Stokkbook como ambiente, selos, Locais, popup de atualização do 1.8.1 → 1.9.0) e o painel de parede do desktop numa TV. **Locais por setor e turno:** rodar o `update_022`, testar de verdade: lançar local com e sem fim, ver o ponto pulsar só em quem está ao vivo, abrir um turno que cruza a meia-noite (3º), exportar Excel, mudar o setor de um equipamento. Falta: mesmo painel/cores no desktop (parede), levar ao APK (`versionCode`), botões de locais frequentes por setor (esperando a lista), relatório fixado por rotina no fim do turno (hoje é montado na hora).
- **v1.8.0 (Stokkbook):** rodar o `update_021` e testar de verdade: concluir um 5S com a caixinha marcada (aparece no feed de quem tem a área), desmarcada (não aparece), reagir/trocar/tirar em dois celulares, supervisor ocultar/reexibir, anular um 5S (post some). Ideias: push de "novo post" (junto da notificação push pendente), comentários, posts de máquina (parada resolvida, recorde) quando as paradas estiverem em uso, post também ao abrir 5S, filtro por área.
- **Menu por ambiente (teste, só site):** avaliar no uso se o menu da Laminação ficou bom; se sim, liberar no APK (tirar `!Capacitor.isNativePlatform()` em `menuGrupos`, aumentar `versionCode`), criar grupos para Trefila e outros ambientes e decidir sobre permissão por módulo.
