#Requires -Version 5.1
<#
  Apply pending Supabase migrations without the broken `supabase --linked` path.

  Why this exists: the CLI's linked mode creates a temporary `cli_login_postgres`
  role through the Management API, and a leftover one from an earlier attempt
  makes that fail with `permission denied to alter role`. A direct connection
  string skips that step entirely.

  The other trap it handles: every migration so far was applied by pasting SQL in
  the dashboard, so the remote history table (`supabase_migrations.
  schema_migrations`) may be empty. `db push` would then try to replay all ~51
  files. The script checks the dry run first and, with -Repair, records the older
  ones as already applied before pushing.

  Usage (in this folder):
      .\db_push.ps1                  # dry run, then ask before applying
      .\db_push.ps1 -Repair          # also record older migrations as applied
      .\db_push.ps1 -Yes             # no prompts (still shows the dry run)

  The password is read masked, used only in memory, and never written to disk.
#>

param(
  [string]$ProjectRef = 'zxjuqpqzyzmegdjttzyz',
  [string]$PoolerHost = 'aws-1-ap-south-1.pooler.supabase.com',
  [switch]$Repair,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath (Split-Path -Parent $PSCommandPath)

# Anything older than this has definitely been applied to live already
# (see docs/handover.md); it is the cut-off for -Repair.
$alreadyLiveBefore = '20261026015100'

$secure = $null
$pw = $env:SUPABASE_DB_PASSWORD
if ([string]::IsNullOrWhiteSpace($pw)) {
  # Masked prompt: the password stays in memory and is never written to disk.
  $secure = Read-Host -AsSecureString 'Database password'
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
} else {
  Write-Host 'Using SUPABASE_DB_PASSWORD from the environment.' -ForegroundColor DarkGray
}
if ($null -ne $secure) { $secure = $null }

if ([string]::IsNullOrWhiteSpace($pw)) {
  Write-Host 'No password given.' -ForegroundColor Red
  exit 1
}

$env:SUPABASE_DB_PASSWORD = $pw
$url = 'postgresql://postgres.{0}:{1}@{2}:5432/postgres' -f `
  $ProjectRef, [uri]::EscapeDataString($pw), $PoolerHost

function Invoke-Supabase {
  param([string[]]$CmdArgs)
  # The CLI writes its progress to stderr; with ErrorActionPreference = Stop that
  # would abort the script, so the native call runs with Continue and the two
  # streams are flattened to text.
  $prev = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $raw = & npx --no-install supabase @CmdArgs --db-url $url 2>&1
  } finally {
    $ErrorActionPreference = $prev
  }
  ($raw | ForEach-Object { if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.Exception.Message } else { "$_" } }) -join "`n"
}

function Get-Planned {
  param([string]$Text)
  # Every migration file is named <14-digit version>_<name>.sql, and the dry run
  # echoes those names. Scanning for the version avoids depending on the CLI's
  # bullet/table formatting. Note: \b cannot be used here — "_" is a word
  # character, so "20261026015100_security…" has no boundary after the digits.
  [regex]::Matches($Text, '(?<!\d)(\d{14})(?!\d)') |
    ForEach-Object { $_.Groups[1].Value } |
    Select-Object -Unique
}

Write-Host ''
Write-Host '== Connecting and planning (dry run) ==' -ForegroundColor Cyan
$dry = Invoke-Supabase @('db', 'push', '--dry-run')

if ($dry -match 'authentication failed|not found \(SQLSTATE XX000\)|ENOTFOUND') {
  Write-Host $dry -ForegroundColor DarkGray
  Write-Host 'Could not connect. Check the password (and that the pooler host is right).' -ForegroundColor Red
  exit 1
}

$planned = Get-Planned $dry
Write-Host ("Pending: {0}" -f ($(if ($planned.Count) { $planned -join ', ' } else { 'none' })))

if ($planned.Count -eq 0) {
  if ($dry -match 'up to date|No migrations') {
    Write-Host 'Nothing to apply.' -ForegroundColor Green
    exit 0
  }
  # Do not claim success when the output simply was not understood.
  Write-Host ''
  Write-Host 'Could not read the plan from the dry run. Its output was:' -ForegroundColor Yellow
  Write-Host $dry -ForegroundColor DarkGray
  exit 3
}

if ($planned.Count -gt 3) {
  Write-Host ''
  Write-Host ("{0} migrations are unrecorded, so the remote history table is empty." -f $planned.Count) -ForegroundColor Yellow
  Write-Host 'That is expected: earlier files were pasted into the dashboard, not pushed.'
  if (-not $Repair) {
    Write-Host ''
    Write-Host 'Re-run with -Repair to record the already-applied ones first:' -ForegroundColor Yellow
    Write-Host '    .\db_push.ps1 -Repair'
    exit 2
  }

  $older = Get-ChildItem supabase\migrations\*.sql |
    ForEach-Object { $_.BaseName.Split('_')[0] } |
    Where-Object { $_ -lt $alreadyLiveBefore } |
    Sort-Object
  Write-Host ("Recording {0} older migrations as applied..." -f $older.Count) -ForegroundColor Cyan
  $repairOut = Invoke-Supabase (@('migration', 'repair', '--status', 'applied') + $older)
  if ($repairOut -match 'error|failed') { Write-Host $repairOut -ForegroundColor Red; exit 1 }
  Write-Host 'History updated. Re-planning...' -ForegroundColor Green

  $dry = Invoke-Supabase @('db', 'push', '--dry-run')
  $planned = Get-Planned $dry
  Write-Host ("Pending now: {0}" -f ($(if ($planned.Count) { $planned -join ', ' } else { 'none' })))
  if ($planned.Count -eq 0) { Write-Host 'Nothing left to apply.' -ForegroundColor Green; exit 0 }
}

Write-Host ''
Write-Host 'Will apply:' -ForegroundColor Cyan
$planned | ForEach-Object { Write-Host "  - $_" }

if (-not $Yes) {
  $answer = Read-Host 'Apply now? (y/N)'
  if ($answer -notmatch '^(y|yes)$') {
    Write-Host 'Nothing applied.' -ForegroundColor Yellow
    exit 0
  }
}

Write-Host ''
Write-Host '== Applying ==' -ForegroundColor Cyan
$push = Invoke-Supabase @('db', 'push', '--include-all')
Write-Host $push

if ($push -match 'Finished|Applying migration|completed') {
  Write-Host 'Done. Verify with the queries in docs/handover.md.' -ForegroundColor Green
} else {
  Write-Host 'Push did not report success — read the output above.' -ForegroundColor Yellow
}
