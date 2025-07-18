<#
.SYNOPSIS
  Full logical MariaDB backup via mysqldump,
  organized by Year\Month folders, and uploaded to Azure using account key.
  Accepts the database name via the -DatabaseName argument.

.PARAMETER DatabaseName
  The name of the database to back up (must exist).
#>

param(
  [string]$DatabaseName,
  [string]$MySqlExe          = "C:\Program Files\MariaDB 11.8\bin\mysql.exe",
  [string]$MySqlDumpExe      = "C:\Program Files\MariaDB 11.8\bin\mysqldump.exe",
  [string]$MySqlUser         = "root",
  [string]$MySqlPassword     = "root@123",
  [string]$StorageAccount    = "stbackuppocc",
  [string]$StorageAccountKey = "OrrTRAlQT1e1mLKlzz0OJM5QfT5h11NE53Vq19AMlNuAYWbIjpUtCx+0lMozy8QLre2rBLgsabOb+AStY05xDA==",
  [string]$ContainerName     = "mariadb-backups",
  [string]$LocalBaseDir      = "$env:USERPROFILE\Backups\MariaDB"
)

# ── Validate input ─────────────────────────────────────────────────────────────
if (-not $DatabaseName) {
  Write-Error "❌ Missing -DatabaseName argument." ; exit 1
}

# ── Load Az.Storage module ─────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
  Install-Module Az.Storage -Scope CurrentUser -Force
}
Import-Module Az.Storage

# ── Check database exists ──────────────────────────────────────────────────────
$dbList = & $MySqlExe `
  --user=$MySqlUser --password=$MySqlPassword `
  --batch --skip-column-names `
  -e "SHOW DATABASES;"
if ($dbList -notcontains $DatabaseName) {
  Write-Error "❌ Database '$DatabaseName' does not exist." ; exit 1
}

# ── Build paths ────────────────────────────────────────────────────────────────
$today         = Get-Date
$yearDir       = Join-Path $LocalBaseDir $today.ToString("yyyy")
$monthDir      = Join-Path $yearDir $today.ToString("MM")
$backupName    = "${DatabaseName}_${today:yyyyMMdd}.bak"
$backupPath    = Join-Path $monthDir $backupName

foreach ($f in @($LocalBaseDir, $yearDir, $monthDir)) {
  if (-not (Test-Path $f)) {
    New-Item -ItemType Directory -Path $f | Out-Null
  }
}

# ── Dump the database ──────────────────────────────────────────────────────────
Write-Host "`n🗃️  Dumping '$DatabaseName' to '$backupPath'" -ForegroundColor Cyan
& $MySqlDumpExe `
  --user=$MySqlUser `
  --password=$MySqlPassword `
  --single-transaction `
  --routines `
  --events `
  $DatabaseName > $backupPath

if (-not (Test-Path $backupPath)) {
  Write-Error "❌ Backup failed—file not created." ; exit 1
}
Write-Host "✔ Local backup created." -ForegroundColor Green

# ── Upload to Azure ────────────────────────────────────────────────────────────
Write-Host "`n📤 Uploading to Azure Storage..." -ForegroundColor Cyan
$ctx = New-AzStorageContext `
  -StorageAccountName $StorageAccount `
  -StorageAccountKey  $StorageAccountKey

Set-AzStorageBlobContent `
  -File      $backupPath `
  -Container $ContainerName `
  -Blob      $backupName `
  -Context   $ctx `
  -Force | Out-Null

Write-Host "`n✅ Backup & upload complete!" -ForegroundColor Green
Write-Host "🔗 https://$StorageAccount.blob.core.windows.net/$ContainerName/$backupName`n"
