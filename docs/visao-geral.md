# STOKK — Visão geral, arquitetura e pastas

> Leia primeiro para se situar: o que é o STOKK, stack e onde fica cada arquivo.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 1. Visão geral

**STOKK** é um app de controle de estoque de pátio e de rendimento metálico para uma
trefilaria/usina de aço. O estoque inicial vem de planilhas exportadas do **TOTVS Protheus**; a
partir daí o pessoal do pátio confere volumes bipando etiquetas, e a produção registra o que foi
consumido e produzido nos laminadores para calcular o **rendimento metálico**.

| Pergunta | Resposta |
|---|---|
| Quem usa | Operadores (pátio/produção) e supervisores (importação, exclusões, histórico) |
| Onde roda | Celular/coletor Android (APK ou navegador), e navegador no computador (site desktop) |
| Onde ficam os dados | Supabase (Postgres), compartilhados entre todos os aparelhos em tempo real |
| Idioma da interface | Português (Brasil) |
| Integração com Protheus | **Somente leitura de planilha** (importação manual). Não há API. |

**Funcionalidades:** início (dashboard de estoque) · bipar etiqueta · estoque · conferência de
inventário · produção (rendimento metálico por equipamento/turno) · importação de planilha ·
histórico de movimentos · exportação para Excel · relatórios no Power BI.

---

## 2. Arquitetura

```
                     ┌──────────────────────────────┐
  Planilha Protheus ─►  App STOKK (React + Vite)     │   APK Android (Capacitor)
  (.xlsx)            │  stokk-vite/src/App.jsx       │   ou navegador (GitHub Pages)
                     └──────────────┬───────────────┘
                                    │ supabase-js (HTTPS + Realtime)
  Site desktop ─────────────────────┤  (arquivo único: public/desktop/index.html)
                                    ▼
                     ┌──────────────────────────────┐
                     │ Supabase                      │
                     │  • Auth (e-mail/senha)        │
                     │  • Postgres + RLS (schema public)
                     │  • Realtime (publication)     │
                     │  • schema bi (views) ◄────────┼──── Power BI Desktop (usuário somente leitura)
                     └──────────────────────────────┘
```

### Stack
| Camada | Tecnologia |
|---|---|
| Front-end do app | **React 18** (JSX), **Vite 5**; porém grande parte da UI é feita com *template strings* e `innerHTML` dentro de `App.jsx` (herança da versão em HTML único) |
| Mobile | **Capacitor 8** (`com.stokk.app`), build Android via GitHub Actions |
| Banco / Auth / Realtime | **Supabase** (`@supabase/supabase-js` ^2) |
| Planilhas | **SheetJS** (`xlsx` 0.18.5) para importar e exportar |
| Leitura de código de barras | `BarcodeDetector` (câmera) e leitor USB/Bluetooth em modo teclado |
| OCR de etiqueta | **Tesseract.js 5** (carregado do jsDelivr sob demanda) |
| Site desktop | HTML/CSS/JS **sem framework**, arquivo único |
| BI | **Power BI Desktop** lendo views do schema `bi` |
| Fontes | Google Fonts (Oswald, IBM Plex Sans, IBM Plex Mono) |

---

## 3. Estrutura de pastas e arquivos

```
barra-app/                          (repositório git na raiz — histórico antigo)
├─ index.html                       Versão ORIGINAL em HTML único (legado, anterior ao Vite)
├─ manifest.json · icons/
├─ schema.sql                       Criação do banco (tabelas, RLS, trigger de perfil, realtime)
├─ update_001 … update_008_*.sql    Migrações incrementais (ver seção 4.4)
├─ README.md                        Guia inicial de configuração do Supabase e do primeiro teste
├─ ESQUEMA_STOKK.md                 Dicionário de dados para o Power BI
├─ GUIA_POWERBI.md                  Conexão, DAX e painéis sugeridos para o Power BI
├─ DOCUMENTACAO_TECNICA.md          (apontador) e docs/  (documentação por área)
├─ CLAUDE.md                        Instruções para o Claude Code (manter esta doc atualizada)
└─ stokk-vite/                      (repositório git próprio — é o que vai para o GitHub)
   ├─ index.html                    Esqueleto HTML + CSS do app (login, topbar, views, nav)
   ├─ src/
   │   ├─ main.jsx                  Entrada do React
   │   ├─ App.jsx                   TODO o app (~3,5 mil linhas)
   │   └─ index.css                 Estilos adicionais
   ├─ public/
   │   ├─ desktop/index.html        Site desktop (arquivo único, ~3,1 mil linhas)
   │   ├─ icons/ · manifest.json
   ├─ android/                      Projeto Android gerado pelo Capacitor
   ├─ capacitor.config.ts           appId com.stokk.app, webDir dist
   ├─ vite.config.js                base '/Stokk-app/' quando GH_PAGES=true; senão '/'
   ├─ .github/workflows/
   │   ├─ android.yml               Gera APK debug a cada push na master
   │   └─ pages.yml                 Publica o site no GitHub Pages a cada push na master
   └─ package.json
```

> **Dois repositórios git:** a raiz `barra-app/` e `stokk-vite/`. O que é publicado (Pages/APK) é
> o `stokk-vite/`. Em 2026-10-09 havia alterações **não commitadas** em `index.html`,
> `public/desktop/index.html`, `src/App.jsx` e `src/index.css` (último commit: `89a6e75`, 2026-09-26).

### Mapa de `src/App.jsx`
O arquivo é um único módulo grande, organizado por seções com comentários `/* ===== ... ===== */`:

| Linhas (aprox.) | Seção |
|---|---|
| 236–280 | Configuração do Supabase (URL, anon key) e `state` global |
| 277–380 | **Adaptador de banco** (`createSupabaseDB`): API `collection().doc().set/update/get/delete`, `onSnapshot`, realtime |
| 380–436 | Autenticação (login, perfil, `applyRoleUI`) |
| 437–545 | Utilitários (toast, beep, formatação), status, armazéns |
| 544–625 | Categoria/bitola/modelo do produto (extraídos da descrição) |
| 662–685 | Tema claro/escuro |
| 685–810 | Casamento de código de lote, parser de etiqueta, OCR |
| 849–935 | Assinaturas de dados e roteador de abas (`setView`, `renderView`) |
| 948–1143 | Início (dashboard) |
| 1144–1720 | Bipar (leitor, câmera, OCR, cadastro manual) |
| 1720–2094 | Estoque (filtros, seleção/exclusão em lote, detalhe do volume, troca de armazém) |
| 2094–2229 | Importar planilha |
| 2229–2727 | Conferência (inventário) e relatório |
| 2727–3482 | **Produção** (registro, dashboard de rendimento, relatório) |
| 3482–3560 | Histórico, exportação XLSX, inicialização |

---
