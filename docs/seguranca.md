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
- **Gestão / Diesel (update_015):** as 5 tabelas do diesel têm RLS por área (`area = any (areas_do_usuario())`) e `anon` sem acesso. Quem lê: contas ativas com a área Gestão. `abastecimentos`: qualquer conta ativa da área insere (em nome de si mesma); compras, conferências da régua, equipamentos e tanques: só supervisor. **Ninguém apaga:** não há DELETE; correção é anulação (permissão de UPDATE só nas colunas `anulado` e `anulado_motivo`, com gatilho que exige motivo e grava quem/quando). A área só é concedida pelo painel/SQL (`usuario_areas`).
- **Gestão / Localização (update_017):** `equipamento_locais` com RLS por área e `anon` sem acesso. Insere qualquer conta ativa da área (só em nome de si mesma e nunca já anulado); anula só supervisor (UPDATE só em `anulado` e `anulado_motivo`, com o gatilho de anulação do diesel). Sem DELETE. **Correção de ocorrência em aberto:** só supervisor (política de UPDATE), só `categoria`, `motivo` e `descricao`; o gatilho zera qualquer tentativa de mexer nos campos da liberação durante a correção e grava `editada_em`/`editada_por`. **Desktop:** os botões de lançar/cadastrar/anular só aparecem conforme o papel, mas quem decide é o banco; o desktop usa o mesmo login e as mesmas políticas do app.
- **5S / fotos (update_018):** `cinco_s` com RLS por área e `anon` sem acesso; abrir = qualquer conta da área (em nome próprio); anular e corrigir só supervisor e concluir por qualquer conta da área, tudo decidido no gatilho `cinco_s_proteger` (valem mesmo por fora do app). Fotos no bucket **privado** `cinco-s` (JPEG, até 2 MB), acessadas só por link temporário de 1 h; políticas de `storage.objects` por pasta de área; **sem update/delete** de foto. O Power BI vê só `bi.cinco_s`, sem fotos. Fotos extras (update_019): `cinco_s_caminhos_ok` obriga todos os caminhos a estarem na pasta da própria área; o gatilho impede mexer nas fotos do antes e nas do depois depois de concluído.
- **Gestão / Paradas e manutenção (update_016):** `ocorrencias` com RLS por área e `anon` sem acesso. Abrir: qualquer conta ativa da área, só em seu próprio nome e já em aberto. Liberar e anular: só supervisor, com permissão de UPDATE só nas colunas da liberação e da anulação; gatilho `ocorrencia_proteger` trava tudo o que já foi liberado/anulado. Sem DELETE. As colunas `aviso_*_em` o app não consegue alterar. **Edge Function, tipo `ocorrencia`:** exige o login do usuário (confere o token), conta ativa na área da ocorrência, e só quem abriu (ou quem liberou) dispara o aviso, até 15 min depois; o texto sai do banco, nunca do que o app enviar; o aviso é reservado de forma atômica (não repete). O segredo do cron não é usado nesse tipo; os outros tipos continuam exigindo `x-cron-secret`.

### Administração de usuários (v1.7.0)
- A tela **Usuários** só aparece para `profiles.admin = true`, mas a trava real é no servidor: a Edge Function `admin-usuarios` recebe o login (JWT) de quem chamou, confere com a chave de serviço se a conta está **ativa e admin** e só então age. A chave de serviço fica só nos segredos do Supabase, nunca no app.
- O campo `admin` **nunca** muda pela tela nem pelo app (gatilho `proteger_profiles` + a função ignora o campo): só por SQL.
- Travas: não apaga conta (bloqueia com `ativo = false`); admin não bloqueia nem rebaixa a si mesmo, nem tira áreas da própria conta; papel/bloqueio de **outro admin** só pelo SQL.
- Senha inicial definida pelo admin (mostrada uma vez na tela para repassar); a senha não é gravada em `admin_acoes`. Mínimo de 8 caracteres.
- Toda ação vai para `admin_acoes`.

### Assinatura e atualização do APK (v1.7.1)
- O APK é assinado com uma chave fixa guardada só nos segredos do GitHub (e uma cópia offline com o dono). Nunca versionar `.jks` (já no `.gitignore`). Perder a chave = todos precisam desinstalar/reinstalar; vazar a chave = qualquer um pode publicar APK que o Android aceita como atualização (trocar a chave e reinstalar).
- O app só baixa de `https://github.com/<repo>/releases/download/…`, confere o SHA-256 do `versao.json` e o Android ainda exige o toque em **Instalar** e que o APK tenha a mesma assinatura. Permissão `REQUEST_INSTALL_PACKAGES` no manifesto.
