# STOKK — Segurança e operação

> Ver também `banco.md` (RLS) e `update_008_seguranca.sql`.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 13. Segurança e operação

- A **anon key** do Supabase está no código (`App.jsx` e site desktop). É pública por design; a proteção real vem da **RLS** e do login.
- **Defesa em profundidade (update_008):** o JavaScript do navegador pode ser editado por qualquer um, então toda autorização está no banco (RLS, permissões por coluna, triggers). Editar o código da página não dá acesso a dados nem permite virar supervisor.
- CDNs com versão fixa (`supabase-js@2.117.1`, `tesseract.js@5.1.1`, `xlsx 0.18.5`). `xlsx 0.18.5` tem falhas conhecidas ao ler planilhas maliciosas; só supervisores importam planilhas (arquivos de fonte confiável).
- Não publicar o `.pbix` em repositório público (pode conter dados).
- Nunca colocar no repositório: `service_role key`, senha do banco ou a senha de `powerbi_leitor`.
- `powerbi_leitor` só lê o schema `bi`, em transação somente leitura, com timeout de 60 s.
- **Pausa do Supabase (plano gratuito):** o projeto pausa após ~1 semana sem uso. Basta retomar no painel; os usuários foram orientados a não deixar pausar.
- Realtime exige as tabelas na publication `supabase_realtime` (feito nos SQLs).
- Backup: o `.pbix` e o banco devem ter cópia antes de alterações grandes.

---
