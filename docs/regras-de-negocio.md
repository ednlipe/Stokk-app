# STOKK — Regras de negócio

> Status, armazéns, conferência, rendimento metálico. App, site e Power BI devem seguir as mesmas regras.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 9. Regras de negócio

### 9.1 Status do volume
`estoque`, `bloqueado`, `transferido`, `baixado`. Para exibição, um volume `estoque` só aparece como **"Em estoque"** depois de contado numa conferência;
antes disso aparece como **"Aguardando conferência"** ou **"Não conferido"**.

### 9.2 Armazéns (selo físico da qualidade)
`02` desconhecido/outro galpão · `03` em análise (reteste) · `92` consumo interno/ajuste PCP · `93` OK para carregar ·
`96` rejeitar · `97` em análise (concessão) · `98` retrabalhar · `FATURADO` · `NAO_LOCALIZADO` (legado; hoje o app **não** move itens para esse armazém).

### 9.3 Conferência de inventário
1. Inicia sessão (nome opcional). Cada pessoa "segue" a sessão ativa; ela é retomada ao recarregar.
2. O **primeiro item bipado define o escopo** (produto) — com confirmação do operador. A lista **esperada** (volumes `estoque` do produto) é congelada em `esperados_snapshot`.
3. Itens de outro produto são rejeitados ("fora do escopo").
4. Cada bipe marca o volume como `contado`.
5. Ao registrar: grupos por status, lista de **faltando** (não localizados → `nao_conferido`, **sem mudar o armazém**), e **não cadastrados**; gera movimento `conferencia`.
6. Supervisor pode excluir a conferência (reverte os itens afetados) e dar baixa em não localizados.

### 9.3.1 Contagem cega (v1.4.0)
Conferência ao contrário: **primeiro bipa tudo, depois compara com a planilha do Protheus**. Não altera o estoque (`volumes`); guarda em `sessoes` (`tipo='cega'`, `itens`, `contados` = lista de lotes).
- **Leitura da etiqueta (código de barras da lateral)** — campos colados, lidos **por posição** (as letras do volume e da corrida mudam e nada depende delas): volume (8) + corrida (6) + peso em kg (4 dígitos) + código do produto (termina na **bitola** `B` + número + `.` + 2 casas, ex. `B4.20`) + quantidade de peças (o que sobra). Ex.: `PCI00096PCI0032202TPAIQ092B4.20100`. Aceita também o código curto de baixo da etiqueta (só o volume). Se não separar produto/peças, o item entra marcado **"revisar"**; código fora do padrão **não é contado** (aparece em "leituras fora do padrão"). Lote repetido não conta duas vezes.
- **Chave de comparação:** o **Volume** da etiqueta é o **Lote** do Protheus.
- **Planilha:** o mesmo relatório do Protheus que a aba Importar lê (blocos `Produto:` + linhas `Saldo / Saldo Inicial`, com armazém e lote). A quantidade vem em **toneladas** (UM `TL`) e vira kg; linhas de saldo **repetidas** no relatório são ignoradas; vendas futuras (`Saída`) são ignoradas.
- **Comparação:** *conferem*, *faltando* (na planilha e não bipado), *sobrando* (bipado e fora da planilha), *peso diferente* (tolerância 1 kg; só quando a etiqueta traz o peso), *em outro armazém* (existe na planilha, mas em armazém fora do filtro escolhido), *produto diferente* (informativo) e *para revisar*. O filtro de armazéns escolhe quais armazéns da planilha entram na conta (nenhum = todos).
- **Fluxo:** Conferência › **Iniciar conferência** › popup "Qual tipo de conferência?" (**Padrão** = como antes; **Cega**) › bipar › **Comparar com a planilha** › (opcional) filtrar armazéns › **Exportar planilha** › **Encerrar e guardar**. Dá para sair e continuar depois; o app retoma a contagem deste aparelho.
- **Limites:** uma pessoa/aparelho por contagem (dois aparelhos na mesma contagem se sobrescrevem); a comparação usa a planilha que você subir (se estiver velha, aparecem falsas diferenças); só roda no app e no site desktop (no desktop, o leitor digita no campo da tela).
- **Código:** núcleo em `src/App.jsx` (bloco "CONTAGEM CEGA — núcleo": `cegaLerEtiqueta`, `cegaLerPlanilha`, `cegaComparar`) e cópia idêntica em `public/desktop/index.html`; testes em `tests/cega_core.test.cjs` (`node tests/cega_core.test.cjs`).

### 9.4 Rendimento metálico
- **Rendimento = soma produzida ÷ soma consumida.** Nunca média de percentuais (vale para dia, turno, mês e total).
- Só entram produções com `etapa = 'finalizada'` e `resultado` preenchido.
- **Cor pelo número exibido (1 casa decimal):** ≥ 99,0 verde · ≥ 98,0 amarelo · abaixo vermelho. (98,96 aparece como 99,0% e fica verde.) Acima de 100% recebe ⚠ ("confira os pesos").
- **Turnos:** 1º 7h–15h20 · 2º 15h–23h20 · 3º 23h–7h20.
- Se a produção não tem turno gravado, deduz pelos cortes **07:10 / 15:10 / 23:10** (minutos 430 / 910 / 1390).
- O **3º turno antes das 07:10 conta para o dia anterior**; `data_producao` gravada tem prioridade.
- **Todo peso é guardado e mostrado em KG** (desde 2026-10-13, `update_009`): `volumes.quantidade`, `movimentos.quantidade` e pesos de produção. A planilha importada vinha em **toneladas** (convertida por `update_010`); o importador do app agora multiplica por 1000 ao importar.

- **Áreas (desde 2026-10-20, `update_012`):** o app tem ambientes separados por área: **Trefilaria** (`trefila`, tudo que existia antes) e **Planta 1 (laminação)** (`planta1`). Cada usuário pertence a uma só área e só vê e grava dados dela; supervisor e operador valem dentro da própria área. Os armazéns são por área (`armazens_area`; os da Planta 1 ainda serão cadastrados). O número do lote é único no banco inteiro. Produtos são compartilhados. Quem precisa ver todas as áreas usa o Power BI.

---

### 9.5 Diesel (ambiente Gestão, v1.5.0)
Núcleo em `src/App.jsx` (bloco "DIESEL — núcleo", cópia idêntica em `public/desktop/index.html`) e testes em `tests/diesel_core.test.cjs` (o teste falha se as duas cópias divergirem) e `tests/diesel_aviso.test.cjs` (aviso da Edge Function).
- **Lançamento anulado nunca entra em conta nenhuma.**
- **Saldo do tanque** = entradas − abastecimentos + ajustes da régua (só conferência com `ajustar = true`).
- **Custo médio ponderado:** a cada compra, novo custo = (saldo × custo + litros × preço) ÷ (saldo + litros). Saída e ajuste não mudam o custo. Saldo negativo conta como zero na média. Sem nenhuma compra, o custo é nulo ("sem custo").
- **Cada abastecimento guarda o custo médio do momento** (`custo_litro`, `custo_total`): o gasto histórico não muda quando o preço do diesel muda, e uma compra lançada com data antiga **não** recalcula abastecimentos já gravados.
- **Medidor:** horímetro/km não pode diminuir (app e gatilho no banco), salvo "troca de medidor", que também não gera consumo. Aviso (não bloqueia) se for igual ao anterior ou se saltar mais de 400 h / 3.000 km.
- **Consumo:** cada abastecimento repõe o que o equipamento gastou desde o anterior (assume tanque do equipamento cheio nos dois). Máquinas em **L/h** = litros ÷ horas; caminhão em **km/L** = km ÷ litros. A média do período é **soma dos litros ÷ soma das horas** (nunca média de médias). O 1º abastecimento do equipamento não gera consumo.
- **Consumo fora do normal:** o último intervalo é marcado se for mais de 50% pior que a média dos anteriores (precisa de pelo menos 3 intervalos antes).
- **Sem abastecer:** conta dias de Brasília entre o último abastecimento válido (ou o cadastro, se nunca abasteceu) e hoje; alerta quando **passa** de `dias_alerta` (padrão 2: avisa no 3º dia). Com `alerta_dias_uteis` conta só segunda a sexta. Equipamento inativo ou com `alerta_ativo = false` não entra.
- **Dias que o diesel dura** = saldo ÷ média diária de litros dos últimos 14 dias (acima de 1 ano mostra "mais de 1 ano").
- **Quem pode:** qualquer pessoa ativa da área Gestão registra abastecimento; só **supervisor** cadastra equipamentos/tanques, registra compra e conferência da régua e anula lançamentos.
- **Conferência da régua:** guarda litros medidos × saldo do app. Sem marcar "ajustar", é só registro; marcando, a diferença passa a valer no saldo.

### 9.6 Paradas e manutenção (ambiente Gestão, v1.5.1)
Núcleo `dslOcorrenciaAberta`, `dslOcorrenciaHoras`, `dslParadasResumo` (mesmo bloco "DIESEL — núcleo", cópia no desktop) e testes em `tests/diesel_core.test.cjs`.
- **Ciclo:** qualquer pessoa da Gestão **abre** a ocorrência (equipamento, categoria *Manutenção* ou *Parada*, motivo da lista, descrição, data/hora que parou); ela fica **em aberto**. Só o **supervisor libera**, na mesma ocorrência: motivo da liberação, o que foi feito, quem pegou o equipamento e data/hora (a conta que liberou fica registrada). Os três textos são obrigatórios.
- **Um equipamento tem no máximo uma ocorrência em aberto.** Não dá para abrir outra enquanto não liberar ou anular.
- **Nada se apaga nem se edita:** liberada ou anulada, a ocorrência fica como está; para corrigir, o supervisor **anula** (com motivo) e abre de novo. Ocorrência anulada não entra em nenhuma conta.
- **Horas paradas** = liberação − abertura (se ainda aberta, até agora). No painel, o período filtra pela data de **abertura**; tempo médio = só das liberadas.
- **Equipamento com ocorrência em aberto não gera "sem abastecer"** (app, desktop e aviso push); o app avisa na tela de Abastecer que ele está parado, mas não bloqueia o lançamento.
- **Correção (v1.5.2):** enquanto está em aberto, o **supervisor** pode corrigir categoria, motivo e descrição (a data de abertura não muda); fica gravado quando e por quem (`editada_em`, `editada_por`). Depois de liberada ou anulada, não muda mais.
- **Aviso push:** ao abrir, os supervisores da área recebem na hora (menos quem abriu); ao liberar, os supervisores e quem abriu (menos quem liberou), com o que foi feito, quem pegou e o tempo parado. Se o aviso falhar, a ocorrência já está salva. Cada aviso sai uma vez só.

### 9.7 Localização dos equipamentos (v1.5.2)
Núcleo `dslLocalAtual` (mesmo bloco "DIESEL — núcleo", cópia no desktop) e teste em `tests/diesel_core.test.cjs`.
- **Texto livre + histórico:** qualquer pessoa da Gestão informa onde o equipamento está (local, observação opcional, desde quando). Cada informação vira uma linha; o **local atual** é a mais recente (pela data/hora informada; se for a mesma hora, a lançada depois). Os anteriores formam o histórico "por onde passou".
- Registro anulado (pelo supervisor, com motivo) não conta; nada se apaga nem se edita.
- Como o texto é livre, o app sugere os nomes já usados (lista de sugestões) para evitar variações do mesmo lugar ("Pátio 2" / "patio2"); avisa se o local informado é igual ao atual.
- A localização é **informada à mão** (não é rastreamento). Rastreio por GPS é outro assunto (ver conversa de 05/11).

### 9.8 5S — Gestão Planta 1 (v1.6.0)
Núcleo `c5*` (bloco "5S — núcleo", cópia idêntica no desktop) e teste em `tests/cinco_s_core.test.cjs`.
- **Fluxo:** o 5S nasce **em aberto** com a foto do ANTES (setor, o que está errado, data/hora); qualquer pessoa da área conclui depois com a foto do DEPOIS e "o que foi feito". Também dá para abrir e concluir no mesmo momento (o app grava em dois passos: abre e conclui; se o segundo falhar, fica em aberto e se conclui pela lista).
- **Regras:** nada se apaga. Supervisor **anula** (com motivo) e **corrige setor/descrição** enquanto está em aberto; concluído não muda mais (para corrigir: anular e abrir de novo). A foto do antes nunca muda.
- **Contas:** só entram os não anulados. "Aberto no período" = aberto dentro do período; "concluído no período" = concluído dentro dele; "em aberto agora" não depende do período. **Em aberto há mais de 7 dias** (`C5_DIAS_ALERTA`) é destacado como atenção. Tempo médio = média de (conclusão − abertura) dos concluídos no período.
- **Setor:** texto livre com sugestão dos já usados; "Laminação", "laminacao" e "LAMINAÇÃO " contam como o mesmo setor (sem acento, sem diferença de maiúscula/espaço).
- **Notificação push do 5S: não faz parte desta versão** (planejada junto com o push web para iPhone).

