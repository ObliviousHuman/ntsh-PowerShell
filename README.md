# ntsh-PowerShell

Miscellaneous PowerShell Scripts

---

## Apply-RDPCert

*This was written for the purposes of getting a LetsEncrypt Certificate for RDP written to the applicable Certificate Store with win-acme.*

### Simplistic functionality executed using the something like the following parameters

```cmd
wacs.exe --renew --baseuri "https://acme-v02.api.letsencrypt.org/" ^
--friendlyname "RDP-FRIENDLYNAME" ^
--installation script ^
--script "PATH_TO_SCRIPTS\Apply-RDPCert.ps1" ^
--scriptparameters "'{CertThumbprint}' '{CertFriendlyName}'"
```

---

## Setup-AcmeChallengeDNS01 (This needs a better name...)

*This was written for the purposes of getting a LetsEncrypt SAN Certificate for multiple domains, and wildcards written to the applicable Certificate Store with win-acme.*

```cmd
wacs.exe --renew --baseuri "https://acme-v02.api.letsencrypt.org/" ^
--friendlyname "WC-SAN-FRIENDLYNAME" ^
--validation script ^
--dnscreatescript "PATH_TO_SCRIPTS\Setup-AcmeChallengeDNS01.ps1" ^
--dnscreatescriptarguments "create {Identifier} {RecordName} {Token}" ^
--dnsdeletescript "PATH_TO_SCRIPTS\Setup-AcmeChallengeDNS01.ps1" ^
--dnsdeletescriptarguments "delete {Identifier} {RecordName} {Token}"
```
