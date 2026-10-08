<#
.SYNOPSIS
    Deploys baseline Group Policy Objects (GPOs) and hardening policies for Active Directory homelab.
.DESCRIPTION
    Configures Kerberos ticket lifetime policies, account lockout thresholds, NTLM restriction
    levels, and advanced audit logging via Group Policy on the homelab.local domain controller.
.NOTES
    Domain: homelab.local
    Target: DC=homelab,DC=local
#>

Import-Module GroupPolicy
Import-Module ActiveDirectory

$DomainName = "homelab.local"
$GpoName = "GPO_Sec_Baseline_Hardening"

Write-Host "[*] Creating Group Policy Object: $GpoName" -ForegroundColor Cyan
$gpo = New-GPO -Name $GpoName -Comment "Homelab AD DS Security Baseline: Kerberos, Lockout, and Audit Policies"

Write-Host "[*] Linking $GpoName to Domain Root ($DomainName)" -ForegroundColor Cyan
New-GPLink -Name $GpoName -Target "DC=homelab,DC=local" -Enforced Yes -LinkOrder 1

# 1. Kerberos Ticket Policy Configuration
Write-Host "[*] Applying Kerberos Policy Defaults via Secedit" -ForegroundColor Yellow
$SeceditInf = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[System Access]
; Maximum tolerance for computer clock synchronization (minutes)
MaxClockSkew = 5
; Maximum lifetime for user ticket (hours)
MaxTicketAge = 10
; Maximum lifetime for service ticket (minutes)
MaxServiceAge = 600
; Maximum lifetime for user ticket renewal (days)
MaxRenewAge = 7
; Enforce user logon restrictions
TicketValidateClient = 1

; Account Lockout Policy
LockoutBadCount = 5
ResetLockoutCount = 15
LockoutDuration = 15

; Password Policy
MinimumPasswordLength = 14
PasswordComplexity = 1
PasswordHistorySize = 24
MaximumPasswordAge = 90
MinimumPasswordAge = 1

[Event Audit]
AuditSystemEvents = 3
AuditLogonEvents = 3
AuditObjectAccess = 0
AuditPrivilegeUse = 3
AuditPolicyChange = 3
AuditAccountManage = 3
AuditProcessTracking = 3
AuditDSAccess = 3
AuditAccountLogon = 3
"@

$InfPath = "$env:TEMP\ad_baseline_sec.inf"
$SdbPath = "$env:TEMP\ad_baseline_sec.sdb"

Set-Content -Path $InfPath -Value $SeceditInf -Encoding Unicode

Write-Host "[*] Importing Security Database Template..." -ForegroundColor Cyan
secedit.exe /import /db $SdbPath /cfg $InfPath /overwrite

Write-Host "[*] Applying Security Policy to Local DC..." -ForegroundColor Cyan
secedit.exe /configure /db $SdbPath /cfg $InfPath /area SECURITYPOLICY

# 2. Advanced Audit Policy Subcategories (PowerShell Auditpol Execution)
Write-Host "[*] Configuring Advanced Subcategory Auditing..." -ForegroundColor Cyan

# Account Logon -> Kerberos Authentication Service (Event ID 4768, 4771)
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable

# Account Logon -> Kerberos Service Ticket Operations (Event ID 4769)
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable

# Account Management -> User Account Management (Event ID 4720, 4726, 4738)
auditpol /set /subcategory:"User Account Management" /success:enable /failure:enable

# Account Management -> Security Group Management (Event ID 4728, 4732, 4756)
auditpol /set /subcategory:"Security Group Management" /success:enable /failure:enable

# Logon/Logoff -> Logon (Event ID 4624, 4625)
auditpol /set /subcategory:"Logon" /success:enable /failure:enable

# Detailed Tracking -> Process Creation (Event ID 4688)
auditpol /set /subcategory:"Process Creation" /success:enable /failure:disable

# Privilege Use -> Sensitive Privilege Use (Event ID 4672)
auditpol /set /subcategory:"Sensitive Privilege Use" /success:enable /failure:enable

# 3. Disable LLMNR via Registry GPO setting
Write-Host "[*] Configuring LLMNR Restriction in GPO..." -ForegroundColor Cyan
Set-GPRegistryValue -Name $GpoName -Key "HKLM\Software\Policies\Microsoft\Windows NT\DNSClient" `
    -ValueName "EnableMulticast" -Type DWord -Value 0

# 4. Enforce NTLMv2 Only (LMCompatibilityLevel = 5: Send NTLMv2 response only, refuse LM & NTLM)
Write-Host "[*] Enforcing NTLMv2 Authentication (LMCompatibilityLevel = 5)..." -ForegroundColor Cyan
Set-GPRegistryValue -Name $GpoName -Key "HKLM\System\CurrentControlSet\Control\Lsa" `
    -ValueName "LMCompatibilityLevel" -Type DWord -Value 5

# 5. Disable SMBv1 Protocol on DC
Write-Host "[*] Disabling SMBv1 Server Protocol..." -ForegroundColor Cyan
Set-GPRegistryValue -Name $GpoName -Key "HKLM\System\CurrentControlSet\Services\LanmanServer\Parameters" `
    -ValueName "SMB1" -Type DWord -Value 0

Write-Host "[+] Active Directory baseline hardening and GPO configuration applied successfully." -ForegroundColor Green
