<#
.SYNOPSIS
    Helper script to manage ACME DNS-01 challenge records via nsupdate on a BIND DNS server.

.DESCRIPTION
    This script is designed to be called by win-acme (or similar ACME clients) to create and delete TXT records
    for DNS-01 challenges. 
    It uses nsupdate with a TSIG key for secure updates to the DNS server.

.PARAMETER Action
    The action to perform: 
    'create' to add a TXT record
    'delete' to remove a specific TXT record.
    
.PARAMETER Identifier
    A unique identifier for the challenge (e.g. a hash of the domain and token). 
    This is for logging and correlation purposes.
    'Identifier' is not used in the DNS update itself but should be included in logs for troubleshooting.

.PARAMETER RecordName
    The name of the DNS record to manage (e.g. "_acme-challenge" or "_acme-challenge.subdomain").
    The script will normalize this to a fully qualified domain name (FQDN) by appending the zone and a trailing dot.
    'RecordName' should not include the zone name, as the script will handle that based on configuration.
    
.PARAMETER Token
    The value of the TXT record to create or delete. 
    This is the ACME challenge token that needs to be present for validation.

.NOTES
    - Requires PowerShell 5.1 or later.
    - The script must have access to nsupdate.exe and the TSIG key file.
    - The script will log detailed information about its execution to a specified log directory.
    - The script will throw exceptions if nsupdate fails or if required files are missing.

.EXAMPLE
    .\Setup-AcmeChallengeDNS01.ps1 -Action create -Identifier "abc123" -RecordName "_acme-challenge" -Token "challenge-token-value"
    Creates a TXT record for the ACME DNS-01 challenge.

 #>

# Requires -Version 5.1
# Requires -RunAsAdministrator
param(
  [Parameter(Mandatory=$true)][ValidateSet("create","delete")][string]$Action,
  [Parameter(Mandatory=$true)][string]$Identifier,
  [Parameter(Mandatory=$true)][string]$RecordName,
  [Parameter(Mandatory=$true)][string]$Token
)

# ----------------------------
# CONFIG
# ----------------------------
# Update these variables with your environment-specific values
$nsupdate = "{nsupdate_path}\nsupdate.exe"  # e.g. D:\example\bin\nsupdate.exe
$keyFile  = "{key_file_path}\key_name.key"  # e.g. D:\example\keys\mykey.key
$server   = "{dns_server}"                  # e.g. ns1.exampledns.com
$ttl      = 300                             # Keep TTL low for ACME challenges (e.g. 300 seconds) to allow for quick propagation and cleanup

# Logging configuration
$logDir   = "{log_directory_path}"          # e.g. "C:\Logs\AcmeChallengeDNS01"
$logFile  = Join-Path $logDir ("winacme-dns-{0}.log" -f (Get-Date -Format "yyyyMMdd"))

# If $true, we will NOT print the full token in logs (recommended)
$redactTokenInLogs = $true

# If $true, run nslookup against the authoritative server after each action
$doNslookup = $true

# ----------------------------
# HELPERS
# ----------------------------
# Helper functions for logging, redaction, and nslookup
# Ensure-Dir: Creates a directory if it doesn't exist
# Write-Log: Writes a timestamped message to the log file 
# Redact: Redacts sensitive values for logging if configured to do so

# Helper function to ensure a directory exists
function Ensure-Dir([string]$path) {
  if (-not (Test-Path -LiteralPath $path)) {
    New-Item -ItemType Directory -Path $path -Force | Out-Null
  }
}

# Simple logging function with timestamp
function Write-Log([string]$message) {
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
  $line = "{0}  {1}" -f $ts, $message
  Add-Content -LiteralPath $logFile -Value $line
}

# Redact token for logs if configured to do so
function Redact([string]$value) {
  if (-not $redactTokenInLogs) { return $value }
  if ([string]::IsNullOrWhiteSpace($value)) { return $value }
  if ($value.Length -le 10) { return "***REDACTED***" }
  # keep first/last 4 chars for correlation
  return "{0}...{1}" -f $value.Substring(0,4), $value.Substring($value.Length-4,4)
}

# Helper function to run nslookup for TXT records
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