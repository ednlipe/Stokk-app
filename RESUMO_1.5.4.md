# STOKK 1.5.4 — Resumo das correções

**Data:** 06/11/2026 · **Commit:** `a4c0faa` · **Versão:** 1.5.4 (`versionCode 14`)
**Origem:** revisão de código do 1.5.3 (painel de Localização no site desktop)

---

## 1. Equipamento em manutenção podia aparecer como "Operando"

**Onde:** app (`src/App.jsx`) e site desktop (`public/desktop/index.html`)

**Problema:** o app e o desktop carregam só as 3.000 ocorrências mais recentes e os 5.000 locais mais recentes. Quando o banco passasse disso:
- uma manutenção aberta há muito tempo ficaria de fora, e o equipamento apareceria verde, como **"Operando"**;
- um equipamento sem local recente apareceria como **"Local não informado"**.

Nenhum erro seria mostrado.

**Correção:** nova função `completarAntigos`, no adaptador do banco, com o mesmo código no app e no desktop. Quando a leitura chega no limite, ela busca à parte:
- as ocorrências ainda em aberto (`liberada_em` vazio, não anuladas);
- o último local válido de cada equipamento que ficou de fora.

Abaixo do limite, que é o caso de hoje, não faz nenhuma consulta a mais.

---

## 2. O painel da TV relia o banco inteiro a cada minuto

**Onde:** só no site desktop (aba Localização)

**Problema:** a releitura automática de 60 segundos relia todas as tabelas, inclusive os 10.000 abastecimentos. Numa TV ligada o dia todo, eram umas 20 requisições por minuto no Supabase.

**Correção:** a releitura passou a usar `refetchTabelas(['ocorrencias','equipamento_locais'])`, só o que o painel mostra. O botão **"↻ Atualizar"** continua relendo tudo.

---

## 3. Um teste nunca rodava

**Onde:** `tests/diesel_aviso.test.cjs`

**Problema:** o teste procurava a pasta `supabase` fora do projeto e dava erro antes de testar qualquer coisa.

**Correção:** caminho ajustado. O teste passa, mas exige **Node 22.13+**. Com o Node 20, rode:

```bash
npx node@22 tests/diesel_aviso.test.cjs
```

---

## Também nesta versão

- **Teste novo** `tests/completar_antigos.test.cjs`: confere a correção 1 com um banco simulado e falha se o app e o desktop ficarem com códigos diferentes.
- **Versão 1.5.4** em `package.json`, `android/app/build.gradle` (`versionCode 14`) e `APP_VERSAO` no desktop.
- **Documentação:** `docs/historico.md`, `docs/pendencias.md`, `docs/app.md`, `docs/desktop.md` e `docs/README.md`.
- **Sem SQL novo:** não precisa rodar nada no Supabase.

---

## Situação dos testes

| Verificação | Resultado |
|---|---|
| `tests/cega_core.test.cjs` | passou |
| `tests/diesel_core.test.cjs` | passou |
| `tests/diesel_aviso.test.cjs` (Node 22) | passou |
| `tests/completar_antigos.test.cjs` | passou |
| `npm run build` | compilou |
| Supabase real / navegador logado | **não testado** |
| APK no celular | **não testado** |

---

## Anotado em `docs/pendencias.md` (ainda não corrigido)

- **O tempo real relê a tabela inteira:** cada abastecimento novo faz todo mundo reler todos os abastecimentos, e depois do primeiro evento o limite deixa de valer. A correção muda o comportamento de todas as áreas, então precisa de teste cuidadoso.
- **Painel de parede (TV):**
  - não mostra quando foi a última atualização com sucesso (sem internet, parece atualizado com dados velhos);
  - a TV pode entrar em modo de espera (falta Wake Lock);
  - perde a tela cheia ao recarregar a página;
  - relógio e período usam o fuso do aparelho, não Brasília;
  - o redesenho a cada 30 s reinicia a rolagem das tabelas;
  - os equipamentos parados aparecem em ordem de código, não pelo tempo parado.

---

## Próximo passo

1. Dar push (`git push`): o GitHub Actions publica o site desktop e gera o APK 1.5.4.
2. Abrir o site e o app logados e conferir se as ocorrências e os locais aparecem normalmente.
3. Só então instalar o APK nos celulares.
