<#
  STOKK — backup do banco (Supabase) e foto da estrutura.

  Como usar (dois cliques em scripts\backup_banco.cmd, ou no PowerShell, na pasta do projeto):
      powershell -NoProfile -ExecutionPolicy Bypass -File scripts\backup_banco.ps1
      ... -SoEstrutura        só a estrutura, sem os dados
      ... -Pasta D:\backups   outra pasta para os dados (padrão: OneDrive\STOKK_backups)

  O que gera:
    banco\estrutura.sql          tabelas, funções, gatilhos, RLS, permissões e views de public e bi.  VAI PARA O GIT.
    banco\estrutura_extras.sql   extensões, tempo real, gatilhos em auth/storage, Storage e crons
                                 (segredos trocados por <SEGREDO>).                                   VAI PARA O GIT.
    <Pasta>\AAAA-MM-DD_HHmm\     dados_public.sql (todas as tabelas de public), dados_auth.sql
                                 (logins, com hash das senhas) e uma cópia da estrutura.               NUNCA NO GIT.

  A senha do banco é pedida na hora, não aparece na tela e não é gravada. A "connection string"
  (sem senha) fica em <Pasta>\conexao.txt para não precisar colar de novo.
  As fotos do 5S (Storage) NÃO entram neste backup. Detalhes: docs/banco.md, seção 4.7.
#>
param(
  [string]$Pasta = '',
  [switch]$SoEstrutura
)

$raiz = Split-Path -Parent $PSScriptRoot
if (-not $Pasta) {
  $base = if ($env:OneDrive) { $env:OneDrive } else { [Environment]::GetFolderPath('MyDocuments') }
  $Pasta = Join-Path $base 'STOKK_backups'
}

function Find-PgBin([string]$nome) {
  # prefere a versão mais nova instalada (o pg_dump precisa ser da mesma versão do servidor ou mais nova)
  $achados = Get-ChildItem "C:\Program Files\PostgreSQL\*\bin\$nome.exe" -ErrorAction SilentlyContinue |
    Sort-Object { $n = 0; [void][int]::TryParse($_.Directory.Parent.Name, [ref]$n); $n } -Descending
  if ($achados) { return @($achados)[0].FullName }
  $c = Get-Command $nome -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}

function Write-Passo([string]$texto, [bool]$ok) {
  if ($ok) { Write-Host "  ok     $texto" -ForegroundColor Green }
  else     { Write-Host "  FALHOU $texto" -ForegroundColor Red }
}

$pgdump = Find-PgBin 'pg_dump'
$psql   = Find-PgBin 'psql'
if (-not $pgdump -or -not $psql) {
  Write-Host 'Não achei o pg_dump/psql. Instale o PostgreSQL (versão 17 ou mais nova) e rode de novo.' -ForegroundColor Red
  exit 1
}

# ---------- conexão (sem senha) ----------
New-Item -ItemType Directory -Force -Path $Pasta | Out-Null
$arqConexao = Join-Path $Pasta 'conexao.txt'
$uri = ''
if (Test-Path $arqConexao) { $uri = ([string](Get-Content $arqConexao -TotalCount 1)).Trim() }
if (-not $uri) {
  Write-Host ''
  Write-Host 'Cole a "connection string" do Supabase: painel > botão Connect > Session pooler > URI.'
  Write-Host 'Pode colar do jeito que vem, com [YOUR-PASSWORD]: a senha é pedida separada e não é gravada.'
  $uri = ([string](Read-Host 'Connection string')).Trim()
}
$m = [regex]::Match($uri, '^postgres(?:ql)?://([^:@/]+)(?::[^@]*)?@([^:/?]+)(?::(\d+))?/([^?\s]+)')
if (-not $m.Success) {
  Write-Host 'Connection string não reconhecida (esperado: postgresql://usuario:senha@servidor:5432/postgres).' -ForegroundColor Red
  if (Test-Path $arqConexao) { Remove-Item $arqConexao -Confirm:$false }
  exit 1
}
$pgUser = $m.Groups[1].Value
$pgHost = $m.Groups[2].Value
$pgPort = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { '5432' }
$pgDb   = $m.Groups[4].Value
Set-Content -Path $arqConexao -Value "postgresql://${pgUser}@${pgHost}:${pgPort}/${pgDb}" -Encoding ASCII

$nomesEnv = 'PGHOST','PGPORT','PGUSER','PGDATABASE','PGPASSWORD','PGSSLMODE','PGCLIENTENCODING','PGAPPNAME','PGCONNECT_TIMEOUT'
try {
  $seg = Read-Host "Senha do banco (usuário $pgUser; não aparece na tela)" -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($seg)
  try { $env:PGPASSWORD = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
  $env:PGHOST = $pgHost; $env:PGPORT = $pgPort; $env:PGUSER = $pgUser; $env:PGDATABASE = $pgDb
  $env:PGSSLMODE = 'require'; $env:PGCLIENTENCODING = 'UTF8'; $env:PGAPPNAME = 'stokk-backup'; $env:PGCONNECT_TIMEOUT = '20'

  Write-Host ''
  Write-Host "Conectando em $pgHost ..."
  $versaoServidor = & $psql -X -A -t -c 'show server_version_num'
  if ($LASTEXITCODE -ne 0 -or -not $versaoServidor) {
    Write-Host 'Não consegui entrar no banco. Confira a senha e se o projeto não está pausado no Supabase.' -ForegroundColor Red
    exit 1
  }
  $majorServidor = [int]([string]$versaoServidor).Trim().Substring(0, 2)
  $majorDump = [int]([regex]::Match((& $pgdump --version), '(\d+)\.').Groups[1].Value)
  if ($majorDump -lt $majorServidor) {
    Write-Host "O pg_dump instalado é $majorDump e o banco é $majorServidor. Instale o PostgreSQL $majorServidor ou mais novo." -ForegroundColor Red
    exit 1
  }
  Write-Host "  ok     conectado (PostgreSQL $majorServidor; pg_dump $majorDump)" -ForegroundColor Green

  $falhas = @()

  # ---------- estrutura (vai para o git) ----------
  $dirBanco = Join-Path $raiz 'banco'
  New-Item -ItemType Directory -Force -Path $dirBanco | Out-Null
  $estrutura = Join-Path $dirBanco 'estrutura.sql'
  $extras    = Join-Path $dirBanco 'estrutura_extras.sql'

  & $pgdump --schema-only --no-owner --schema=public --schema=bi "--file=$estrutura"
  $ok = ($LASTEXITCODE -eq 0); Write-Passo 'estrutura de public e bi  -> banco\estrutura.sql' $ok
  if (-not $ok) { $falhas += 'estrutura' }

  & $psql -X -q -A -t -f (Join-Path $PSScriptRoot 'backup_extras.sql') -o $extras
  $ok = ($LASTEXITCODE -eq 0); Write-Passo 'extras (Storage, tempo real, crons) -> banco\estrutura_extras.sql' $ok
  if (-not $ok) { $falhas += 'extras' }

  # confere se escapou algum segredo para os arquivos que vão para o git
  $padroes = 'eyJ[A-Za-z0-9_-]{20,}', '-----BEGIN', "(?i)password\s+'[^'<]", '(?i)"x-cron-secret"\s*:\s*"[^"<]', '(?i)bearer\s+[A-Za-z0-9_.-]{20,}'
  $suspeitos = Select-String -Path $estrutura, $extras -Pattern $padroes -ErrorAction SilentlyContinue
  if ($suspeitos) {
    Write-Host ''
    Write-Host 'ATENÇÃO: parece haver segredo nos arquivos da estrutura. NÃO faça commit antes de revisar:' -ForegroundColor Yellow
    $suspeitos | ForEach-Object { Write-Host ("  {0}:{1}" -f (Split-Path $_.Path -Leaf), $_.LineNumber) -ForegroundColor Yellow }
    $falhas += 'segredo-na-estrutura'
  }

  # ---------- dados (NUNCA no git) ----------
  if (-not $SoEstrutura) {
    $dirDia = Join-Path $Pasta (Get-Date -Format 'yyyy-MM-dd_HHmm')
    New-Item -ItemType Directory -Force -Path $dirDia | Out-Null

    & $pgdump --data-only --no-owner --schema=public ("--file=" + (Join-Path $dirDia 'dados_public.sql'))
    $ok = ($LASTEXITCODE -eq 0); Write-Passo 'dados de public           -> dados_public.sql' $ok
    if (-not $ok) { $falhas += 'dados_public' }

    & $pgdump --data-only --no-owner --table=auth.users --table=auth.identities ("--file=" + (Join-Path $dirDia 'dados_auth.sql'))
    $ok = ($LASTEXITCODE -eq 0); Write-Passo 'logins (auth.users)       -> dados_auth.sql' $ok
    if (-not $ok) { $falhas += 'dados_auth' }

    Copy-Item $estrutura, $extras -Destination $dirDia -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host "Backup dos dados em: $dirDia"
    Get-ChildItem $dirDia | ForEach-Object { Write-Host ("  {0,-24} {1,10:N0} KB" -f $_.Name, [math]::Ceiling($_.Length / 1KB)) }
    Write-Host 'Esses arquivos têm dados reais (nomes, estoque, hash de senhas): não mande para o git nem para outras pessoas.' -ForegroundColor Yellow
  }

  Write-Host ''
  if ($falhas.Count) {
    Write-Host ("Terminou com problemas: " + ($falhas -join ', ')) -ForegroundColor Red
    exit 2
  }
  Write-Host 'Pronto. A estrutura atualizada está em banco\ (confira com "git diff banco" antes do commit).' -ForegroundColor Green
}
finally {
  foreach ($n in $nomesEnv) { Remove-Item "Env:$n" -ErrorAction SilentlyContinue }
}
