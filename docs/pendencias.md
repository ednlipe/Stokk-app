# STOKK — Limitações conhecidas e backlog

> 
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

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
