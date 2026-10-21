# STOKK — Segurança e operação

> Ver também `banco.md` (RLS) e `update_008_seguranca.sql`.
> Índice geral: [`docs/README.md`](README.md). Regra: mudou algo desta área, atualize ESTE arquivo e uma linha em [`historico.md`](historico.md).

## 13. Segurança e operação

- A **anon key** do Supabase está no código (`App.jsx` e site desktop). É pública por design; a proteção real vem da **RLS** e do login.
- **Defesa em profundidade (update_008):** o JavaScript do navegador pode ser editado por qualquer um, então toda autorização está no banco (RLS, permissões por coluna, triggers). Editar o código da página não dá acesso a dados nem permite virar supervisor.
- CDNs com versão fixa (`supabase-js@2.117.1`, `tesseract.js@5.1.1`, `xlsx 0.18.5`). `xlsx 0.18.5` tem falhas conhecidas ao ler planilhas maliciosas; só supervisores importam planilhas (arquivos de fonte confiável).
- **Áreas (update_012):** cada usuário tem uma única área (`profiles.area`). A RLS de `volumes`, `movimentos`, `sessoes` e `producoes` exige `area = area_do_usuario()` (função que devolve nulo para conta bloqueada, sem área ou com área desativada). Registro novo recebe a área de quem o cria; inserir ou mover registro para outra área é negado. `profiles.area` só muda pelo painel/SQL Editor (coluna fora do `grant update` e trigger `proteger_profiles`). Conta nova nasce sem área e bloqueada. O app mostra "sem permissão" (e desloga) se a conta não tem área ou a área está desativada, mas a proteção real é a RLS. `produtos` continua compartilhado entre as áreas. O Power BI (`powerbi_leitor`) enxerga todas as áreas. Sem acesso multiárea pelo app nesta versão.
- **Várias áreas (update_013):** a lista de áreas da pessoa fica em `usuario_areas` (+ `profiles.area` como principal), só alterável pelo painel/SQL Editor. A RLS usa `areas_do_usuario()`. O nível (`role`) vale para todas as áreas da pessoa. O gatilho `proteger_area_registro` impede mover registro de área pelo app (lote já existente em outra área gera erro, pois `volumes.lote` é único entre áreas). Power BI continua vendo todas as áreas.
- Não publicar o `.pbix` em repositório público (pode conter dados).
- Nunca colocar no repositório: `service_role key`, senha do banco ou a senha de `powerbi_leitor`.
- `powerbi_leitor` só lê o schema `bi`, em transação somente leitura, com timeout de 60 s.
- **Pausa do Supabase (plano gratuito):** o projeto pausa após ~1 semana sem uso. Basta retomar no painel; os usuários foram orientados a não deixar pausar.
- Realtime exige as tabelas na publication `supabase_realtime` (feito nos SQLs).
- Backup: o `.pbix` e o banco devem ter cópia antes de alterações grandes.

---
