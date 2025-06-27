# ntsh-PowerShell

Miscellaneous PowerShell Scripts

---

## Apply-RDPCert

*This was written for the purposes of getting a LetsEncrypt Certificate for RDP written to the applicable Certificate Store with win-acme.*

### Simplistic functionality executed using the soemthing like the following parameters

```cmd
wacs.exe --renew --baseuri "https://acme-v02.api.letsencrypt.org/" ^
--friendlyname "RDP-FRIENDLYNAME" ^
--installation script ^
--script "PATH_TO_SCRIPTS\Apply-RDPCert.ps1" ^
--scriptparameters "'{CertThumbprint}' '{CertFriendlyName}'"
```

---
