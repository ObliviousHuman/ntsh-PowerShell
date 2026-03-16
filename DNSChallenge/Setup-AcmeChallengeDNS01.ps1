param(
  [Parameter(Mandatory=$true)][ValidateSet("create","delete")][string]$Action,
  [Parameter(Mandatory=$true)][string]$Identifier,
  [Parameter(Mandatory=$true)][string]$RecordName,
  [Parameter(Mandatory=$true)][string]$Token
)

# ----------------------------
# CONFIG
# ----------------------------
$nsupdate = "{nsupdate_path}\nsupdate.exe"  # e.g. D:\example\bin\nsupdate.exe
$keyFile  = "{key_file_path}\key_name.key"  # e.g. D:\example\keys\mykey.key
$server   = "{dns_server}"                  # e.g. ns1.exampledns.com
$ttl      = 300

$logDir   = "{log_directory_path}"          # e.g. "C:\Logs\AcmeChallengeDNS01"
$logFile  = Join-Path $logDir ("winacme-dns-{0}.log" -f (Get-Date -Format "yyyyMMdd"))

# If $true, we will NOT print the full token in logs (recommended)
$redactTokenInLogs = $true

# If $true, run nslookup against the authoritative server after each action
$doNslookup = $true

# ----------------------------
# HELPERS
# ----------------------------
function Ensure-Dir([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

function Write-Log([string]$message) {
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  $line = "{0}  {1}" -f $ts, $message
  Add-Content -LiteralPath $logFile -Value $line
}

function Redact([string]$value) {
  if (-not $redactTokenInLogs) { return $value }
  if ([string]::IsNullOrWhiteSpace($value)) { return $value }
  if ($value.Length -le 10) { return "***REDACTED***" }
  # keep first/last 4 chars for correlation
  return "{0}...{1}" -f $value.Substring(0,4), $value.Substring($value.Length-4,4)
}

function Run-NsLookupTxt([string]$fqdn, [string]$dnsServer) {
  # returns multi-line string
  $out = & nslookup.exe -type=TXT $fqdn $dnsServer 2>&1 | Out-String
  return $out.TrimEnd()
}

# ----------------------------
# START
# ----------------------------
Ensure-Dir $logDir

Write-Log "------------------------------------------------------------"
Write-Log "START Action=$Action Identifier='$Identifier' RecordName='$RecordName' Token='$(Redact $Token)'"
Write-Log "Config: server=$server ttl=$ttl nsupdate='$nsupdate' keyFile='$keyFile' redactToken=$redactTokenInLogs nslookup=$doNslookup"
Write-Log "User: $env:USERNAME  Host: $env:COMPUTERNAME  PID: $PID"

# Validate paths early
if (-not (Test-Path -LiteralPath $nsupdate)) { Write-Log "ERROR nsupdate not found at '$nsupdate'"; throw "nsupdate.exe not found at: $nsupdate" }
if (-not (Test-Path -LiteralPath $keyFile))  { Write-Log "ERROR key file not found at '$keyFile'"; throw "TSIG key file not found at: $keyFile" }

# Normalize record name to FQDN with trailing dot
$fqdn = $RecordName.Trim().TrimEnd('.') + '.'
Write-Log "Normalized FQDN: $fqdn"

# Build nsupdate commands (no 'zone' line - BIND selects correct zone)
if ($Action -eq "create") {
  $cmds = @"
server $server
update add $fqdn $ttl IN TXT "$Token"
send
"@
} else {
  # Delete ONLY the matching token (safe when multiple tokens exist)
  $cmds = @"
server $server
update delete $fqdn IN TXT "$Token"
send
"@
}

# Log commands (token optionally redacted)
$cmdsForLog = if ($redactTokenInLogs) { $cmds.Replace($Token, (Redact $Token)) } else { $cmds }
Write-Log "nsupdate commands:`n$cmdsForLog"

# Execute nsupdate and capture output
try {
  $nsupdateOutput = $cmds | & "$nsupdate" -k "$keyFile" 2>&1 | Out-String
  $exitCode = $LASTEXITCODE
} catch {
  Write-Log "EXCEPTION running nsupdate: $($_.Exception.Message)"
  throw
}

Write-Log ("nsupdate exitcode={0}" -f $exitCode)
if (-not [string]::IsNullOrWhiteSpace($nsupdateOutput)) {
  Write-Log ("nsupdate output:`n{0}" -f $nsupdateOutput.TrimEnd())
} else {
  Write-Log "nsupdate output: <empty>"
}

# Optional authoritative lookup after action
if ($doNslookup) {
  try {
    $lookup = Run-NsLookupTxt $fqdn $server
    Write-Log "Authoritative nslookup result:`n$lookup"
  } catch {
    Write-Log "WARNING nslookup failed: $($_.Exception.Message)"
  }
}

# Fail if nsupdate failed
if ($exitCode -ne 0) {
  Write-Log "ERROR nsupdate returned non-zero exit code."
  throw "nsupdate $Action failed (exit code $exitCode) for Identifier='$Identifier' Record='$fqdn'"
}

Write-Log "SUCCESS Action=$Action for $fqdn"
Write-Log "END"