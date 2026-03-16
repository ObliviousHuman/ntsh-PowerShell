param(
  [Parameter(Mandatory=$true)][string]$RecordName,  # e.g. _acme-challenge
  [Parameter(Mandatory=$true)][string]$Token,       # TXT value
  [Parameter(Mandatory=$true)][string]$ZoneName     # e.g. exampledomain.tld
)

$nsupdate = "{nsupdate_path}\nsupdate.exe"  # e.g. D:\DNS\bin\nsupdate.exe
$keyFile  = "{key_file_path}\key_name.key"  # e.g. D:\DNS\keys\mykey.key
$server   = "{dns_server}"                  # e.g. ns1.exampledns.com

$fqdn = "$RecordName.$ZoneName."

# Delete only the TXT that matches this token (safe when multiple tokens exist)
$cmds = @"
server $server
zone $ZoneName.
update delete $fqdn IN TXT "$Token"
send
"@

$cmds | & $nsupdate -k $keyFile
if ($LASTEXITCODE -ne 0) { throw "nsupdate cleanup failed with exit code $LASTEXITCODE" }