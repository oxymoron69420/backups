<#
.SYNOPSIS
  Full logical backup of multiple MariaDB databases via mysqldump,
  organized by year/month folders and uploaded to Azure Blob Storage.

.PARAMETER DatabaseName
  Comma-separated list of DB names OR "*" to back up all
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
  Write-Error "❌ You must supply -DatabaseName (e.g. 'test' or 'test,mydb,*')." ; exit 1
}

# ── Load Az.Storage ───────────────────────────────────────────────────────────
if (-not (Get-Module -ListAvailable -Name Az.Storage)) {
  Install-Module Az.Storage -Scope CurrentUser -Force
}
Import-Module Az.Storage

# ── Fetch list of actual databases ────────────────────────────────────────────
$available = & $MySqlExe `
  --user=$MySqlUser --password=$MySqlPassword `
  --batch --skip-column-names `
  -e "SHOW DATABASES;" |
  Where-Object { $_ -notin @("information_schema","performance_schema","mysql","sys") }

if ($DatabaseName -eq "*") {
  $targets = $available
} else {
  $targets = $DatabaseName.Split(",") | ForEach-Object { $_.Trim() }
  $missing = $targets | Where-Object { $available -notcontains $_ }
  if ($missing) {
    Write-Error "❌ Invalid database(s): $($missing -join ", ")" ; exit 1
  }
}

# ── Timestamp pieces ───────────────────────────────────────────────────────────
$today      = Get-Date
$year       = $today.ToString("yyyy")
$month      = $today.ToString("MM")
$stamp      = $today.ToString("yyyyMMdd")
$yearFolder = Join-Path $LocalBaseDir $year
$monthFolder= Join-Path $yearFolder $month
foreach ($f in @($LocalBaseDir, $yearFolder, $monthFolder)) {
  if (-not (Test-Path $f)) { New-Item -Path $f -ItemType Directory | Out-Null }
}

# ── Backup each database ───────────────────────────────────────────────────────
foreach ($db in $targets) {
  $bakName = "${db}_${stamp}.bak"
  $bakPath = Join-Path $monthFolder $bakName

  Write-Host "`n🗃️  Backing up '$db' → '$bakPath'" -ForegroundColor Cyan
  & $MySqlDumpExe `
    --user=$MySqlUser `
    --password=$MySqlPassword `
    --single-transaction `
    --routines `
    --events `
    $db > $bakPath

  if (-not (Test-Path $bakPath)) {
    Write-Error "❌ Backup failed for '$db'. Skipping upload." ; continue
  }

  Write-Host "✔ Backup saved locally." -ForegroundColor Green

  $ctx = New-AzStorageContext `
    -StorageAccountName $StorageAccount `
    -StorageAccountKey  $StorageAccountKey

  Set-AzStorageBlobContent `
    -File      $bakPath `
    -Container $ContainerName `
    -Blob      $bakName `
    -Context   $ctx `
    -Force | Out-Null

  Write-Host "✅ Uploaded to Azure: https://${StorageAccount}.blob.core.windows.net/${ContainerName}/${bakName}" -ForegroundColor Green
}

Write-Host "`n🎉 All requested backups complete!`n"
