# STOKK — Limitações conhecidas e backlog

> 
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).
>
> **Revisado em 25/11/2026** contra o código, o `historico.md` e a foto do banco de produção de 23/11 (`banco/estrutura.sql`). Regra usada: SQL "aplicado" só quando a foto mostra; "testado em produção" só quando há registro escrito. O resto continua pendente.

## 13. Pendências do Diesel (v1.5.0)

- **SQL:** `update_015_diesel.sql`, `016` e `017` **estão aplicados em produção** (foto do banco de 23/11, §13.4). Não há registro de teste no uso real.
- **Cron do diesel não existe** (§13.4): o aviso "sem abastecer" (`{"tipo":"diesel"}`) nunca dispara. Não há registro de que a Edge Function publicada em produção já tem os tipos `diesel` e `ocorrencia` (a última publicação registrada é a v3 de 17/10). Conferir e, se o aviso ainda for desejado, publicar a função e criar o cron (`deploy.md`).
- Testar no uso real: cadastro de tanque/equipamentos, compra, abastecimento (máquina e caminhão), anulação, conferência da régua, painel do desktop e o push de "sem abastecer".
- Confirmar com a empresa: quantos tanques e equipamentos; quem lança abastecimento e compra; se o horímetro do caminhão também importa; prazo de guarda dos registros; se a empresa quer cópia dos dados em outro lugar (Excel online/Power Automate, ver conversa de 01/11).
- Limite conhecido: o consumo assume que cada abastecimento enche o equipamento; abastecimento parcial distorce o L/h e o km/L daquele intervalo.
- Compra lançada com data antiga não recalcula o custo dos abastecimentos já gravados (de propósito).

## 13.7 Releitura do tempo real (25/11, só na branch `teste`)

- **Corrigido na branch `teste`, não publicado:** o evento do realtime relê com a ordem e o limite da assinatura (`releituraRealtime` + `fetchParams`, app e desktop), junta eventos seguidos e descarta resposta atrasada (`leituraSeq`). Detalhes em `app.md` › Tempo real. Teste automático com banco simulado: `tests/realtime_core.test.cjs` (adaptador, inclusive `completarAntigos` no evento para ocorrências, locais e 5S). Ele não prova que o Supabase entrega os eventos; isso continua pendente abaixo.
- **Gestão validada com o Supabase real em 25/11** (link de teste, build do commit `f356a47`, conta `op.teste`; app numa aba e desktop › Localização/Abastecimento noutra, sem "Atualizar"): local novo do CM01 apareceu no desktop em 2,3 s; abastecimento da EP01 em 1,0 s; ocorrência da PC01 ("Em manutenção") em 1,5 s; 3 trechos seguidos da EP02 terminaram no último em 0,3 s. Cada evento fez **uma** leitura com a ordem e o limite da assinatura (ex.: `equipamento_locais?…order=data_hora.desc,id.asc&offset=0&limit=1000`). Nenhum erro no console do desktop. Nos 3 trechos seguidos as leituras não chegaram a se sobrepor (eventos a 1,7 s e 0,7 s, leituras de 0,3–0,7 s), então a junção de eventos só está coberta pelo teste automático.
- **Falta validar com o Supabase real:** Trefila (`movimentos` continua com os 300 mais recentes em ordem depois de um evento), 5S (Gestão Planta 1), num celular/APK e em produção.
- **Dados de teste deixados no `stokk-teste` (25/11):** ocorrência **em aberto** da PC01 ("teste realtime 1c"; liberar ou anular com um supervisor da Gestão), locais "teste realtime 1a" (CM01) e "1d-1/2/3" (EP02), abastecimento de 40 L da EP01 ("teste realtime 1b").
- **Muda o que se via depois de um evento:** antes, o primeiro evento fazia a assinatura com limite carregar a tabela inteira (sem querer). Agora fica sempre no limite. Quem dependia disso sem saber:
  - `sessoes` (limite 100): uma conferência **ativa** mais antiga que as 100 sessões mais recentes não aparece (não há `completarAntigos` para `sessoes`). Na leitura inicial já era assim. Se isso acontecer na prática, incluir `sessoes` ativas no `completarAntigos` (app e desktop, `tests/completar_antigos.test.cjs`).
  - `movimentos` (300) e `producoes` (1000): telas que somam "tudo" só veem as linhas mais recentes, como já acontecia na leitura inicial.

## 13.6 Mudança para a Cloudflare (23/11)

- Seguir a ordem de `deploy.md` §12.1. **Não tornar o repositório privado antes de todos os celulares estarem na versão que procura a atualização na Cloudflare.**
- Feito em 23/11: token e segredos no GitHub, 1ª publicação (`stokk.khay-entertainment.workers.dev`) e link de teste (`teste-stokk.khay-entertainment.workers.dev`). A 1.10.8 procura a atualização na Cloudflare. A 1.10.9 foi publicada lá (o `versao.json` do GitHub e o da Cloudflare têm o mesmo `sha256`, conferido com o APK baixado).
- Falta: **todos os celulares na 1.10.8 ou mais nova** antes de fechar o repositório; conferir **num celular** que a atualização 1.10.8 → 1.10.9 chegou pela Cloudflare.
- Depois: avisar o endereço novo do desktop; desligar `pages.yml` e o passo da Release no `android.yml`; tirar `GH_PAGES`/`/Stokk-app/` do `vite.config.js`.

## 13.5 Ambiente de teste (23/11)

- Banco de teste montado em 23/11. Contas de teste: `teste@teste.com` (**supervisor**, Trefila e Planta 1) e `op.teste@teste.com` (**operador**, Gestão). A `op.teste` está com `profiles.admin = true`, o que só serve para ver a tela Usuários: tirar se não for de propósito.
- Feito: site de teste na Cloudflare (`teste-stokk.khay-entertainment.workers.dev`, `cloudflare-teste.yml`, roda os testes antes); RLS real conferida com a `op.teste` na Gestão (1.10.9, 23/11).
- Falta: entrar no app de teste e conferir as telas da Trefila, da Planta 1 e da Gestão Planta 1; rodar os testes também antes da publicação da `master`; APK de teste (`com.stokk.app.teste`, precisa do pacote no Firebase); publicar as Edge Functions no teste quando for testar Usuários/avisos.
- Biometria desligada na 1.10.7 (23/11): conferir num celular que o app abre sem pedir digital.
- 1ª junção `teste` → `master` feita em 23/11 (v1.10.6). Conferir no celular de alguém da fábrica que o 5S e as ocorrências salvam na produção (não salvavam no app da 1.9.0 até a 1.10.5).

## 13.4 Backup e estrutura do banco (23/11 — 1º backup feito)

- **1º backup em 23/11/2026 00:07** (produção, PostgreSQL 17.6): `banco/estrutura.sql` (27 tabelas, 20 funções, 32 gatilhos, 54 políticas, 15 views), `banco/estrutura_extras.sql` e os dados em `OneDrive\STOKK_backups\2026-11-23_0007` (27 tabelas de `public` e 6 logins). Conferido: nenhum segredo nos arquivos de `banco/` (os 3 crons saíram com `<SEGREDO>`). Já está no git.
- **O que a foto mostrou da produção:** os `update_008` e `012` a `023` **estão aplicados**, e o `024` desde 23/11. As seções deste arquivo já foram ajustadas a isso (25/11).
- **Cron do diesel não existe:** só há os crons `push-conferencia`, `push-inventario` e `push-rendimento` (jobs 6, 7, 8). O aviso "sem abastecer" (`{"tipo":"diesel"}`) nunca dispara. Criar pelo `docs/deploy.md`, se o aviso ainda for desejado.
- `schema_atual.sql` ficou superado por `banco/estrutura.sql`: pode ser apagado ou marcado como histórico.
- A cada execução, as linhas `\restrict`/`\unrestrict` do `estrutura.sql` mudam (chave aleatória de segurança do `pg_dump` 17.6+/18). É normal aparecerem no `git diff`.
- **Backup automático** (ainda não existe; plano grátis sem backup): decidir entre o Agendador de Tarefas do Windows (precisa da senha guardada no PC) ou GitHub Actions (o repositório é público; os dados teriam que sair **criptografados**, porque artefatos de repositório público podem ser baixados por terceiros).
- **Fotos do 5S fora do backup** (bucket `cinco-s`): falta uma rotina que baixe as fotos novas pela API do Storage.
- **Restauração:** a estrutura e os cadastros foram montados num projeto vazio (o `stokk-teste`, 23/11). Falta testar a restauração **dos dados completos** (`dados_public.sql`, `dados_auth.sql`).

## 13.1 Pendências de Paradas e manutenção (v1.5.1)

- `update_016_paradas.sql` **aplicado em produção** (foto de 23/11). Falta: conferir se a Edge Function publicada atende o tipo `ocorrencia` (§13) e testar o aviso real no celular: abrir como operador → supervisor recebe; liberar → supervisor e quem abriu recebem.
- Confirmar com a empresa: a lista de motivos (`MANUT_MOTIVOS` e `MANUT_LIBERACAO` em `src/App.jsx`) e se o **operador/responsável** também deve poder liberar (hoje só o supervisor libera; mudar exige alterar a política `ocorrencias_update` e as colunas liberadas).
- Quem libera digita à mão "quem pegou o equipamento" (texto livre). Se quiser escolher da lista de pessoas, é uma melhoria futura.
- Se o app ficar sem internet ao abrir/liberar, a ocorrência não é gravada (o app mostra o erro); o aviso push falho não é reenviado.
- Sem foto/anexo na ocorrência e sem ligação com o checklist de segurança (ideia futura).
- Não testado com bloqueio real da RLS (1.10.9): liberar e corrigir ocorrência.

## 13.2 Pendências de Localização e lançamentos no desktop (v1.5.2)

- `update_017_localizacao.sql`, `022`, `023` e `024` **aplicados em produção** (foto de 23/11). Não há registro de teste no uso real: o operador informa o local no celular, o supervisor vê no desktop e no app; correção de ocorrência em aberto; lançar abastecimento e cadastrar pelo desktop.
- **v1.5.3 (desktop):** testar o "Modo parede" em tela cheia na TV/monitor real (tamanho das letras, quantidade de cartões que cabem sem rolar). Se houver muitos equipamentos, avaliar rolagem automática.
- **Painel de parede (revisão do 1.5.3, ainda abertos):** não mostra quando foi a última leitura com sucesso (sem internet, a tela parece atualizada com dados velhos); sem Wake Lock (a TV pode dormir); a tela cheia se perde ao recarregar a página (falta `?parede=1`/modo quiosque); relógio e período usam o fuso do aparelho, não Brasília; o redesenho a cada 30 s reinicia a rolagem das tabelas fora do modo parede; parados ordenados por código, não por tempo parado.
- **v1.5.4:** testar com o Supabase real que o painel e o app continuam mostrando ocorrências e locais (a busca extra `completarAntigos` só entra quando a leitura atinge o limite: 3.000 ocorrências / 5.000 locais). Desde 25/11 (branch `teste`) ela também roda na releitura do realtime (§13.7).
- `tests/diesel_aviso.test.cjs` e `tests/admin_usuarios.test.cjs` precisam de **Node 22.13+** (`stripTypeScriptTypes`). Com Node 20: `npx node@22 tests/diesel_aviso.test.cjs`. No GitHub (`cloudflare-teste.yml`, Node 22) rodam.
- **Local:** desde a v1.9.1 é escolhido numa lista fixa (`LOC_LOCAIS`: Planta 1, Planta 2, Trefila, no LOC-CORE). Registros antigos de texto livre continuam valendo. Conferir com a equipe se a lista basta (hoje não há "Outro") e se Atividade obrigatória / Solicitante opcional está bom.
- A localização é informada à mão e pode ficar desatualizada; o app mostra "há quanto tempo" para ajudar. Rastreio automático (celular corporativo/GPS) continua só como ideia.
- No desktop, quem lança pelo PC aparece com o nome da conta; se várias pessoas usarem o mesmo PC/login, os registros ficam no mesmo nome (cada pessoa deveria entrar com a própria conta).
- Corrigir ocorrência é só do supervisor. Se o operador também precisar corrigir a própria abertura, é mudança de política (RLS) e de coluna liberada.

## 13.3 Pendências do 5S da Gestão Planta 1 (v1.6.0)

- `update_018_cinco_s.sql` e `019` **aplicados em produção** (foto de 23/11). No app, abrir e concluir 5S não funcionava da 1.9.0 até a 1.10.5 (corrigido na 1.10.6, §13.5). Falta conferir no uso real: abrir com foto no celular, concluir depois, 3 a 5 fotos (tempo de envio em rede móvel; com 10 fotos por registro o espaço sobe para ≈ 1–2 MB), desktop (galeria e resumo), anular/corrigir como supervisor. Não testado com bloqueio real da RLS (1.10.9): concluir 5S.
- **v1.6.2:** o turno do 5S usa o relógio do aparelho (como o resto do desktop), não o de Brasília; o app do celular ainda não mostra turno (só o desktop). Se precisar, levar a faixa de turno para o app.
- **Notificação do 5S (pedido do usuário, adiada):** avisar todos da Planta 1 quando um 5S for aberto/concluído, e avisar supervisor de 5S aberto há muito tempo. Faz parte do trabalho de push, junto com o item abaixo.
- **Push no navegador/iPhone (adiado):** exige PWA (manifesto, ícone, service worker), Firebase web (config + chave VAPID, públicas) e salvar o token de cada aparelho; no iPhone só funciona com iOS 16.4+ e o site adicionado à Tela de Início.
- **Sem fila offline:** sem internet a foto não é enviada (o app avisa e deixa tentar de novo). Se a Planta 1 tiver pontos sem sinal, vale uma fila local (IndexedDB) para enviar depois.
- **Espaço:** ≈ 0,3–0,6 MB por 5S com uma foto em cada lado (até ≈ 2 MB com 5 + 5); plano grátis = 1 GB (≈ 2–3 mil registros). Acompanhar em Supabase → Storage; depois, plano pago ou arquivar fotos antigas (o app não apaga foto).
- Miniaturas: o app mostra a própria foto reduzida (~200 KB) em tamanho pequeno nas listas; se ficar pesado em rede móvel, gerar miniaturas.
- A foto pode ser da galeria (não só da câmera); a data da foto não é conferida (vale a data informada).

## 14. Limitações conhecidas

1. **Leituras com limite:** `volumes` e `produtos` são lidos inteiros em páginas de 1000 (desde a v1.4.2). Assinaturas com limite trazem só as linhas mais recentes: `movimentos` 300, `sessoes` 100, `producoes` 1000 e, na Gestão, `tanque_entradas` 2.000, `abastecimentos` 10.000, `tanque_medicoes` 1.000, `ocorrencias` 3.000, `equipamento_locais` 5.000, `cinco_s` 5.000. Só ocorrências, locais e 5S têm `completarAntigos` (§13.7).
2. **Tempo real:** cada evento relê a assinatura inteira (até o limite), não só a linha alterada. Desde 25/11 (branch `teste`) respeita o limite e a ordem (§13.7). Antes relia a tabela inteira.
3. `App.jsx` é um arquivo único de ~6,7 mil linhas com HTML em *template strings* (difícil de testar/dividir; ver `mapa-app-jsx.md`).
4. Excluir produção finalizada (supervisor, relatório › "excluir este registro de produção", 14/10) só apaga o registro de rendimento e **não reverte o estoque**. **Status:** não testado em produção.
4b. A tela **Histórico** não tem botão no menu do app (só no site desktop).
5. O parser de etiqueta foi validado só com o padrão `PCI…`; faltam amostras reais de `MB…` e `BCJ…`.
6. Importação do Protheus é manual (planilha), sem API.
7. OCR depende de internet (Tesseract carregado do jsDelivr).
8. O site desktop não registra produções nem edita estoque além do que já faz hoje.
9. Power BI: atualização manual (ou agendada só após publicar no serviço, que exige conta corporativa).
10. `powerbi_leitor` lê as views `bi` fora da RLS: manter senha forte e fora do repositório. (`update_008_seguranca.sql` foi executado em produção em 11/10.)
11. Aviso da build: chave `situacao` repetida num objeto de rótulos de `src/App.jsx` (perto da linha 6677, mesmo valor nas duas). Não quebra nada.

---

## 15. Backlog

- Rotina diária (GitHub Actions) + função `ping()` no banco para evitar a pausa do Supabase gratuito.
- Exclusão de produção finalizada **com reversão de estoque** (hoje só apaga o registro).
- "Pinger"/botão de restauração para o Supabase pausado.
- Impressão de etiquetas.
- Integração com a API do Protheus.
- Ajuste do parser com texto real do leitor USB (`MB…`, `BCJ…`).
- Confirmar e aplicar as 34 medidas do `medidas_stokk.json`; concluir a página "Painel" do Power BI; segunda página de estoque/conferências.
- Roteiro de apresentação para a diretoria (o app com dados reais primeiro; o Power BI como complemento).
- Aba Produção também no app com o mesmo visual do desktop (gráfico e perda por equipamento).
- Comprar/validar o leitor de código de barras de longo alcance.
- Dividir o `src/App.jsx` em módulos (`mapa-app-jsx.md`), só quando não houver correções funcionais ou pendências prioritárias.

---

- [ ] Unidade kg: `update_009_unidade_kg.sql` e `update_010_importados_kg.sql` rodados em produção (14/10). Falta: trocar as medidas do Power BI para `quantidade_kg` (cards em kg) e conferir o volume cadastrado à mão (digitado em t?).
- [x] Importador da planilha converte t→kg ao importar (2026-10-14).
- Push (3 tipos, crons 6, 7 e 8 existem na foto de 23/11): testar manualmente `conferencia` e `rendimento` e conferir os disparos automáticos (`select status_code, content from net._http_response order by created desc limit 5;`); finalizar/excluir as 2 conferências de teste; confirmar o ícone da notificação (1.2.1) num celular; decidir os próximos tipos de aviso (conta nova aguardando liberação, produção esquecida, material em análise/armazém 03, volumes liberados 93, resumo do turno); rendimento conta produções por data de finalização (não por `data_producao` do turno), ajustar se necessário.
- **Áreas (v1.3.0):** `update_012`/`013` aplicados (foto de 23/11). Falta: cadastrar os armazéns da Planta 1 em `armazens_area`; atualizar o Power BI (colunas `area`/`area_nome`, segmentação por área); testar em campo. Limites conhecidos: `volumes.lote` único entre áreas; nível (role) único para todas as áreas; `produtos` compartilhado; importação de planilha só grava na área do usuário; definir com o gestor da Planta 1 o que muda (barras e rolos, produção/rendimento fica para depois). Planta 1: aba Produção/Rendimento escondida; definir com o gestor o rendimento da laminação (entradas, saídas, perdas, meta) antes de reabrir.
- **Contagem cega (v1.4.0):** `update_014` aplicado (foto de 23/11: `sessoes.tipo` e `sessoes.itens`). Falta: testar com o coletor Zebra/Bluetooth e com uma planilha do Protheus do **mesmo produto** das etiquetas (tela soldada); confirmar que o código de produto da etiqueta é o mesmo do Protheus (hoje só informativo); definir se duas pessoas contam a mesma contagem (hoje cada contagem é de um aparelho); confirmar se o relatório do Protheus usado traz sempre `UM: TL`.

- **Desktop sem as mudanças de 26/10** (reabrir conferência/contagem, status do material em lote, grupos recolhidos ao selecionar, "Não localizado" no Excel). Só o app foi atualizado (conferido em 25/11: o desktop não tem "Reabrir conferência"/"Reabrir contagem"). Status: não testado em produção.

- **Lacuna no histórico `movimentos` (até 27/10).** A última linha de qualquer tipo é de 09/10/2026. O `update_008_seguranca.sql` (executado em 11/10) deixou `authenticated` só com INSERT e SELECT em `movimentos`, mas o app gravava com upsert (exige UPDATE) e recebia `permission denied for table movimentos`. Corrigido em 27/10 (INSERT puro em `src/App.jsx`). Ações feitas entre ~11/10 e a correção podem ter alterado `volumes` sem deixar movimento; não recriar histórico retroativo. Conferências registradas nesse período podem ter a sessão salva mas os status dos volumes (`contado`/`nao_conferido`) não aplicados: reabrir e registrar de novo reaplica. Status: aguardando confirmação em produção.
- **v1.7.0 (Usuários):** `update_020` aplicado (foto de 23/11: `admin_acoes`). Falta: confirmar que a função `admin-usuarios` está publicada em produção e testar com uma conta de teste (criar, entrar com ela, bloquear, reativar, trocar área). Ideias futuras: versão desktop da tela; a pessoa trocar a própria senha no app; ver o registro `admin_acoes` na tela; convite por e-mail em vez de senha inicial.
- **v1.7.1 (atualização do APK):** o `android.yml` já gera o APK assinado e publica a Release `apk-latest` (1.10.9 publicada em 23/11). Falta registro de teste num aparelho: o popup, o download e o instalador. Ideia futura: botão "Procurar atualização" no app.
- **Excel "Controle de uso":** definir **Centro de custo** (campo no app?) e regra de **HE**; avaliar envio automático ao Excel Online (Power Automate, precisa Microsoft 365) e perfil de leitura para o coordenador.
- **v1.9.0 (pacote completo): testar em APK real** (menu por ambiente, Stokkbook como ambiente, selos, Locais, popup de atualização) e o painel de parede do desktop numa TV. **Locais por setor e turno** (`update_022` aplicado): testar de verdade: lançar local com e sem fim, ver o ponto pulsar só em quem está ao vivo, abrir um turno que cruza a meia-noite (3º), exportar Excel, mudar o setor de um equipamento. Falta: botões de locais frequentes por setor (esperando a lista), relatório fixado por rotina no fim do turno (hoje é montado na hora).
- **v1.8.0 (Stokkbook):** `update_021` aplicado (foto de 23/11). Testar de verdade: concluir um 5S com a caixinha marcada (aparece no feed de quem tem a área), desmarcada (não aparece), reagir/trocar/tirar em dois celulares, supervisor ocultar/reexibir, anular um 5S (post some). Ideias: push de "novo post" (junto da notificação push pendente), comentários, posts de máquina (parada resolvida, recorde) quando as paradas estiverem em uso, post também ao abrir 5S, filtro por área.
- **Menu por ambiente:** desde a v1.9.0 vale no site e no APK (`MENU_NO_APK`/`modoSite()`), com os grupos Laminação Planta 1 e Trefila (`GRUPOS_MENU`). Falta: avaliar no uso, criar grupos para outros ambientes e decidir sobre permissão por módulo (hoje é por área).
