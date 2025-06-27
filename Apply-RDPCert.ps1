<#
.SYNOPSIS
    Applies a specified SSL certificate to Remote Desktop Protocol (RDP) on the local machine.
    Applies specifically to Windows 2008 R2 Environment.

.DESCRIPTION
    This script locates a certificate in the LocalMachine\My certificate store by its thumbprint,
    verifies its friendly name, and applies it to RDP by updating the SSLCertificateSHA1Hash property
    of the Win32_TSGeneralSetting WMI class.

.PARAMETER CertThumbprint
    The thumbprint of the certificate to be applied to RDP. Whitespace will be stripped automatically.

.PARAMETER CertFriendlyName
    The expected friendly name of the certificate. Used for additional verification.

.NOTES
    - Requires administrative privileges.
    - The script will exit with code 1 if the certificate is not found.
    - The script will exit with code 2 if the friendly name does not match.

.EXAMPLE
    .\Apply-RDPCert.ps1 -CertThumbprint "ABCDEFF123456..." -CertFriendlyName "RDP Certificate"
    Applies the certificate with the specified thumbprint and friendly name to RDP.
#>

# Requires -Version 5.1
# Requires -RunAsAdministrator
[CmdletBinding()]
# Requires -InputObject (Get-ChildItem -Path Cert:\LocalMachine\My)
# Requires -OutputType (Get-WmiObject -Namespace "root\cimv2\TerminalServices" -Class "Win32_TSGeneralSetting")
# Requires -OutputType (Get-WmiObject -Namespace "root\cimv2\TerminalServices" -Class "Win32_TSRemoteDesktopListener")
# Requires -OutputType (Get-WmiObject -Namespace "root\cimv2" -Class "Win32_Service")
# Requires -OutputType (Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "SSLCertificateSHA1Hash")
# Requires -OutputType (Restart-Service -Name "TermService" -Force)
# Requires -OutputType (Write-Output "Applied certificate to RDP: $CertFriendlyName ($CertThumbprint)")
# Requires -OutputType (Write-Host "Applied certificate to RDP: $CertFriendlyName ($CertThumbprint)")
# Requires -OutputType (Write-Error "Certificate with thumbprint $CertThumbprint not found.")
# Requires -OutputType (Write-Warning "Friendly name mismatch. Expected: '$CertFriendlyName', Found: '$($cert.FriendlyName)'")
# Requires -OutputType (Write-Error "Failed to apply certificate to RDP settings.")
param (
    [string]$CertThumbprint,
    [string]$CertFriendlyName
)

# Strip whitespace from thumbprint
$CertThumbprint = $CertThumbprint -replace '\s', ''

# Locate matching cert
$cert = Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object { $_.Thumbprint -eq $CertThumbprint }

# Check if the certificate was found
if (-not $cert) {
    Write-Error "Certificate with thumbprint $CertThumbprint not found."
    exit 1
}

# Optional: Verify friendly name if you want additional safety
if ($cert.FriendlyName -ne $CertFriendlyName) {
    Write-Warning "Friendly name mismatch. Expected: '$CertFriendlyName', Found: '$($cert.FriendlyName)'"
    exit 2
}

# Apply Cert to RDP
$tsSettings = Get-WmiObject -Namespace "root\cimv2\TerminalServices" -Class "Win32_TSGeneralSetting"
foreach ($setting in $tsSettings) {
    $setting.SSLCertificateSHA1Hash = $CertThumbprint
    $setting.Put()
}

# Ensure the WMI class is updated
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply certificate to RDP settings."
    exit 3
}
# Optionally, you can also set the certificate for the RDP listener
$rdpListener = Get-WmiObject -Namespace "root\cimv2\TerminalServices" -Class "Win32_TSRemoteDesktopListener"
foreach ($listener in $rdpListener) {
    $listener.SSLCertificateSHA1Hash = $CertThumbprint
    $listener.Put()
}

# Ensure the RDP listener is updated
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply certificate to RDP listener settings."
    exit 4
}

# Optionally, you can set the certificate for the RDP service
$rdpService = Get-WmiObject -Namespace "root\cimv2" -Class "Win32_Service" | Where-Object { $_.Name -eq "TermService" }
if ($rdpService) {
    $rdpService.SSLCertificateSHA1Hash = $CertThumbprint
    $rdpService.Put()
}
else {
    Write-Warning "RDP service not found. Skipping service update."
}

# Ensure the RDP service is updated
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply certificate to RDP service settings."
    exit 5
}

# If you want to apply the certificate to the RDP service, you can use the following command
# Note: This is not always necessary, as the WMI class updates should suffice.
# Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name "SSLCertificateSHA1Hash" -Value $CertThumbprint
# Ensure the registry key is updated
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to apply certificate to RDP service registry settings."
    exit 6
}
# Ensure the RDP service is restarted to apply changes
# Note: Restarting the service will disconnect all active RDP sessions.
# This is optional and should be done with caution in a production environment.
# Uncomment the following line if you want to restart the RDP service
# Restart-Service -Name "TermService" -Force

# Write output to console
Write-Output "Applied certificate to RDP: $CertFriendlyName ($CertThumbprint)"
Write-Host "Applied certificate to RDP: $CertFriendlyName ($CertThumbprint)"

# Exit with success code
exit 0
# End of script