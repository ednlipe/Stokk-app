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
