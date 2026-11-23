<#
  STOKK — monta o banco do AMBIENTE DE TESTE num projeto Supabase NOVO e vazio, a partir da foto
  da estrutura (banco/estrutura.sql + banco/estrutura_extras.sql). Ver docs/ambiente-teste.md.

  Como usar (na pasta do projeto):
      powershell -NoProfile -ExecutionPolicy Bypass -File scripts\montar_banco_teste.ps1

  O que faz, nesta ordem (cada passo é tudo-ou-nada: se der erro, aquele passo não deixa nada pela metade):
    1. confere que a conexão NÃO é da produção (compara com ambientes.json) e que o banco está vazio;
    2. cria o papel powerbi_leitor (sem login) e as extensões usadas;
    3. roda banco/estrutura.sql (tabelas, funções, gatilhos, RLS, permissões, views do Power BI);
    4. roda banco/estrutura_extras.sql (tempo real, gatilho que cria o perfil, bucket e políticas do Storage);
       os crons NÃO são criados (no teste não há avisos automáticos);
    5. copia só os CADASTROS do último backup (áreas, armazéns, produtos, equipamentos, tanques), sem
       movimentos, conferências nem nomes de pessoas (quem cadastrou fica vazio);
    6. ativa as contas de teste que você criou no painel (supervisor e operador, com todas as áreas).

  A senha do banco de TESTE é pedida na hora e não é gravada. A connection string (sem senha) fica em
  <Pasta>\conexao_teste.txt. Nunca aponta para a produção: o script se recusa.
#>
param(
  [string]$Pasta = ''
)

try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch {}   # acentos das mensagens do psql
$raiz = Split-Path -Parent $PSScriptRoot
if (-not $Pasta) {
  $base = if ($env:OneDrive) { $env:OneDrive } else { [Environment]::GetFolderPath('MyDocuments') }
  $Pasta = Join-Path $base 'STOKK_backups'
}

function Find-PgBin([string]$nome) {
  $achados = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\$nome.exe" -ErrorAction SilentlyContinue |
    Sort-Object { $n = 0; [void][int]::TryParse($_.Directory.Parent.Name, [ref]$n); $n } -Descending
  if ($achados) { return @($achados)[0].FullName }
  $c = Get-Command $nome -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}
function Write-Passo([string]$texto, [bool]$ok) {
  if ($ok) { Write-Host "  ok     $texto" -ForegroundColor Green } else { Write-Host "  FALHOU $texto" -ForegroundColor Red }
}
function Stop-Montagem([string]$msg) { Write-Host ''; Write-Host $msg -ForegroundColor Red; exit 1 }
$utf8 = New-Object Text.UTF8Encoding($false)

$psql = Find-PgBin 'psql'
if (-not $psql) { Stop-Montagem 'Não achei o psql. Instale o PostgreSQL (17 ou mais novo).' }
foreach ($f in 'banco\estrutura.sql', 'banco\estrutura_extras.sql', 'ambientes.json') {
  if (-not (Test-Path (Join-Path $raiz $f))) { Stop-Montagem "Falta o arquivo $f. Rode antes o scripts\backup_banco.ps1 na produção." }
}

# referência da produção (para recusar)
$amb = Get-Content (Join-Path $raiz 'ambientes.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$refProd = [regex]::Match([string]$amb.producao.url, 'https://([a-z0-9]+)\.supabase\.co').Groups[1].Value
if (-not $refProd) { Stop-Montagem 'Não consegui ler a URL da produção em ambientes.json.' }

# ---------- conexão do TESTE (sem senha) ----------
New-Item -ItemType Directory -Force -Path $Pasta | Out-Null
$arqConexao = Join-Path $Pasta 'conexao_teste.txt'
$uri = ''
if (Test-Path $arqConexao) { $uri = ([string](Get-Content $arqConexao -TotalCount 1)).Trim() }
if (-not $uri) {
  Write-Host ''
  Write-Host 'Cole a "connection string" do projeto de TESTE (stokk-teste): painel > Connect > URI.' -ForegroundColor Cyan
  Write-Host 'Pode colar com [YOUR-PASSWORD]: a senha é pedida separada e não é gravada.'
  $uri = ([string](Read-Host 'Connection string do TESTE')).Trim()
}
$m = [regex]::Match($uri, '^postgres(?:ql)?://([^:@/]+)(?::[^@]*)?@([^:/?]+)(?::(\d+))?/([^?\s]+)')
if (-not $m.Success) { Stop-Montagem 'Connection string não reconhecida.' }
$pgUser = $m.Groups[1].Value; $pgHost = $m.Groups[2].Value
$pgPort = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { '5432' }
$pgDb = $m.Groups[4].Value
if (($pgHost + ' ' + $pgUser) -match [regex]::Escape($refProd)) {
  if (Test-Path $arqConexao) { Remove-Item $arqConexao -Confirm:$false }
  Stop-Montagem "PAREI: essa connection string é da PRODUÇÃO ($refProd). Use a do projeto stokk-teste."
}
Set-Content -Path $arqConexao -Value "postgresql://${pgUser}@${pgHost}:${pgPort}/${pgDb}" -Encoding ASCII

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('stokk_teste_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
$nomesEnv = 'PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD','PGSSLMODE','PGCLIENTENCODING','PGAPPNAME','PGCONNECT_TIMEOUT'
try {
  $seg = Read-Host "Senha do banco de TESTE (usuário $pgUser; não aparece na tela)" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seg)
  try { $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  $env:PGHOST = $pgHost; $env:PGPORT = $pgPort; $env:PGUSER = $pgUser; $env:PGDATABASE = $pgDb
  $env:PGSSLMODE = 'require'; $env:PGCLIENTENCODING = 'UTF8'; $env:PGAPPNAME = 'stokk-montar-teste'; $env:PGCONNECT_TIMEOUT = '20'

  Write-Host ''
  Write-Host "Conectando em $pgHost ..."
  $jaTem = & $psql -X -A -t -c "select to_regclass('public.areas') is not null"
  if ($LASTEXITCODE -ne 0) { Stop-Montagem 'Não consegui entrar no banco de teste. Confira a senha.' }
  Write-Passo 'conectado no banco de TESTE' $true
  if (([string]$jaTem).Trim() -eq 't') {
    Stop-Montagem ('Esse banco já tem as tabelas do STOKK (já foi montado). Para montar de novo do zero, ' +
      'apague e recrie o projeto stokk-teste no Supabase. Só para ativar contas, use consultas\teste_ativar_usuarios.sql.')
  }

  $sqlArgs = @('-X', '-q', '-v', 'ON_ERROR_STOP=1', '-1')

  # ---------- 2. papel e extensões ----------
  $prep = Join-Path $tmp '1_preparar.sql'
  [IO.File]::WriteAllText($prep, @"
do `$`$ begin
  if not exists (select 1 from pg_roles where rolname = 'powerbi_leitor') then
    create role powerbi_leitor nologin;   -- no teste não tem login: o Power BI usa só a produção
  end if;
end `$`$;
create extension if not exists "uuid-ossp" with schema extensions;
create extension if not exists pgcrypto with schema extensions;
-- Projeto novo do Supabase dá acesso total às tabelas/funções novas para anon/authenticated/service_role.
-- Na produção isso foi trocado por permissões explícitas (update_008 e seguintes). Desligando o padrão AQUI,
-- as tabelas nascem só com o dono e os GRANT/REVOKE do estrutura.sql deixam as permissões IGUAIS às da
-- produção; o próprio estrutura.sql recoloca, no fim, as permissões padrão que a produção tem.
alter default privileges for role postgres in schema public revoke all on tables    from anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public revoke all on functions from anon, authenticated, service_role;
"@, $utf8)
  & $psql @sqlArgs -f $prep
  $ok = ($LASTEXITCODE -eq 0); Write-Passo 'papel powerbi_leitor (sem login) e extensões' $ok
  if (-not $ok) { Stop-Montagem 'Parei no passo 2. Nada da estrutura foi criado.' }

  # ---------- 3. estrutura ----------
  # ajustes para um projeto Supabase novo (o arquivo do git não muda; a cópia ajustada fica na pasta temporária):
  #  - o schema public já existe -> "create schema if not exists";
  #  - o comentário do schema public e as permissões padrão do supabase_admin (só o Supabase pode mexer;
  #    projeto novo já vem com elas) são pulados.
  $estr = Get-Content (Join-Path $raiz 'banco\estrutura.sql') -Encoding UTF8 |
    Where-Object { $_ -notmatch '^COMMENT ON SCHEMA public ' -and $_ -notmatch '^ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin ' } |
    ForEach-Object { $_ -replace '^CREATE SCHEMA (\w+);$', 'CREATE SCHEMA IF NOT EXISTS $1;' }
  $estrTeste = Join-Path $tmp '2_estrutura.sql'
  [IO.File]::WriteAllLines($estrTeste, [string[]]$estr, $utf8)
  & $psql @sqlArgs -o NUL -f $estrTeste
  $ok = ($LASTEXITCODE -eq 0); Write-Passo 'estrutura (banco\estrutura.sql)' $ok
  if (-not $ok) { Stop-Montagem 'Parei no passo 3 (a estrutura foi desfeita). Mande a mensagem de erro acima para análise.' }

  # ---------- 4. extras (sem extensões nem crons: só as linhas de comando) ----------
  $linhas = Get-Content (Join-Path $raiz 'banco\estrutura_extras.sql') -Encoding UTF8 |
    Where-Object { $_.Trim() -and -not $_.TrimStart().StartsWith('--') -and $_ -notmatch '^\s*create extension' }
  $extras = Join-Path $tmp '2b_extras.sql'
  [IO.File]::WriteAllLines($extras, [string[]]$linhas, $utf8)
  & $psql @sqlArgs -f $extras
  $ok = ($LASTEXITCODE -eq 0); Write-Passo 'tempo real, gatilho do perfil, Storage (banco\estrutura_extras.sql)' $ok
  if (-not $ok) { Stop-Montagem 'Parei no passo 4. A estrutura (passo 3) ficou; mande a mensagem de erro acima para análise.' }

  # ---------- 5. cadastros do último backup ----------
  $ultimo = Get-ChildItem $Pasta -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path (Join-Path $_.FullName 'dados_public.sql') } |
    Sort-Object Name -Descending | Select-Object -First 1
  if (-not $ultimo) {
    Write-Host ("  --     sem backup de dados em $Pasta" + ': cadastros não copiados (cadastre pelo app).') -ForegroundColor Yellow
  } else {
    $dados = [IO.File]::ReadAllLines((Join-Path $ultimo.FullName 'dados_public.sql'), $utf8)
    $tabelas = 'areas', 'armazens_area', 'produtos', 'equipamentos', 'tanques'   # nesta ordem (chaves estrangeiras)
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("set client_encoding = 'UTF8'; set standard_conforming_strings = on;")
    foreach ($t in $tabelas) {
      $i = [Array]::FindIndex($dados, [Predicate[string]]{ param($l) $l.StartsWith("COPY public.$t (") })
      if ($i -lt 0) { continue }
      $cab = $dados[$i] -replace "^COPY public\.$t ", "COPY tmp_$t "
      [void]$sb.AppendLine("create temp table tmp_$t (like public.$t) on commit drop;")
      [void]$sb.AppendLine($cab)
      $j = $i + 1
      while ($j -lt $dados.Length -and $dados[$j] -ne '\.') { [void]$sb.AppendLine($dados[$j]); $j++ }
      [void]$sb.AppendLine('\.')
      if ($dados[$i] -match '\busuario_id\b') { [void]$sb.AppendLine("update tmp_$t set usuario_id = null, usuario_nome = null;") }
      [void]$sb.AppendLine("insert into public.$t select * from tmp_$t on conflict do nothing;")
    }
    $cad = Join-Path $tmp '3_cadastros.sql'
    [IO.File]::WriteAllText($cad, $sb.ToString(), $utf8)
    & $psql @sqlArgs -f $cad
    $ok = ($LASTEXITCODE -eq 0); Write-Passo ("cadastros do backup " + $ultimo.Name + ' (áreas, armazéns, produtos, equipamentos, tanques)') $ok
    if (-not $ok) { Write-Host '         a estrutura ficou pronta; os cadastros podem ser feitos pelo app.' -ForegroundColor Yellow }
  }

  # ---------- 6. contas de teste ----------
  Write-Host ''
  Write-Host 'Agora crie as contas de teste no painel do projeto stokk-teste:' -ForegroundColor Cyan
  Write-Host '  Authentication > Users > Add user > Create new user (marque "Auto Confirm User").'
  Write-Host '  Sugestão: uma de supervisor e uma de operador (e-mails inventados servem, ex.: supervisor@teste.stokk).'
  Write-Host '  Use senhas SÓ do teste (nunca as mesmas da produção).'
  Write-Host ''
  $ativar = Join-Path $raiz 'consultas\teste_ativar_usuarios.sql'
  foreach ($papel in 'supervisor', 'operador') {
    $email = ([string](Read-Host "E-mail da conta $papel de teste (Enter para pular)")).Trim().ToLower()
    if (-not $email) { continue }
    if ($email -notmatch '^[^\s@'']+@[^\s@'']+\.[^\s@'']+$') { Write-Host "  e-mail inválido, pulei: $email" -ForegroundColor Yellow; continue }
    & $psql -X -q -v ON_ERROR_STOP=1 -v "email=$email" -v "papel=$papel" -f $ativar
    $ok = ($LASTEXITCODE -eq 0); Write-Passo "conta $email ativada como $papel (todas as áreas)" $ok
  }

  Write-Host ''
  Write-Host 'Banco de TESTE pronto. No PC: npm run dev (já usa o teste). Ver docs\ambiente-teste.md.' -ForegroundColor Green
}
finally {
  foreach ($n in $nomesEnv) { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }
  Remove-Item $tmp -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue
}
