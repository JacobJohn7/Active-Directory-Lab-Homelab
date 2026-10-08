# Active Directory Domain Services (AD DS) & Domain-Joined Workstation Lab

Implementation details, PowerShell deployment scripts, and DNS/Kerberos telemetry from setting up an Active Directory Domain Controller (`DC01` - `192.168.56.10`) running Windows Server 2019 and a domain-joined Windows 10 workstation (`192.168.56.108`) on a VirtualBox network (`vboxnet0`).

---

## Infrastructure Topology

```text
                        +---------------------------------------+
                        |  pfSense 2.7.2 Firewall & Gateway     |
                        |  LAN: 192.168.56.254 (vboxnet0)       |
                        +---------------------------------------+
                                            |
                    +-----------------------+-----------------------+
                    | (vboxnet0 - 192.168.56.0/24 Default Gateway: .254) |
                    |                                               |
     +--------------+--------------+                +---------------+--------------+
     | Domain Controller (DC01)    |                | Domain Workstation (WIN10)   |
     | Windows Server 2019         |                | Windows 10 Enterprise        |
     | IP: 192.168.56.10           |                | IP: 192.168.56.108           |
     | Domain: homelab.local       |                | Domain: HOMELAB\             |
     | MAC: 08:00:27:21:13:3C      |                | MAC: 08:00:27:56:92:00       |
     +-----------------------------+                +------------------------------+
```

---

## Active Directory Infrastructure Setup

### 1. Forest & Root Domain Creation (`homelab.local`)
- Domain Name: `homelab.local` (NetBIOS: `HOMELAB`)
- Domain Controller: `dc01.homelab.local` (`192.168.56.10`)
- Active Directory Services: AD DS, AD Integrated DNS, Kerberos KDC, LDAP/LDAPS, Global Catalog.

### 2. Organizational Unit (OU) & User Provisioning (`scripts/Deploy-ADLab.ps1`)

Automated Active Directory object provisioning executed via PowerShell:

```powershell
Import-Module ActiveDirectory

# Create Organizational Units
New-ADOrganizationalUnit -Name "OUs_Employees" -Path "DC=homelab,DC=local"
New-ADOrganizationalUnit -Name "OUs_Groups" -Path "DC=homelab,DC=local"

# Create Security Group
New-ADGroup -Name "Sec_Tier1_SOC" -GroupScope Global -GroupCategory Security -Path "OU=OUs_Groups,DC=homelab,DC=local"

# Create User & Assign Group Membership
$Password = ConvertTo-SecureString "P@ssw0rd2026!Sec" -AsPlainText -Force
New-ADUser -sAMAccountName "analyst01" -GivenName "SOC" -Surname "Analyst" `
           -UserPrincipalName "analyst01@homelab.local" -Path "OU=OUs_Employees,DC=homelab,DC=local" `
           -AccountPassword $Password -Enabled $true

Add-ADGroupMember -Identity "Sec_Tier1_SOC" -Members "analyst01"
```

### 3. GPO Security Baseline & Advanced Auditing (`scripts/Deploy-AD-GPO-Hardening.ps1`)

Automated GPO creation and security template application (`config/GPO_Sec_Baseline.inf`):
- **Kerberos Ticket Lifetimes:** User ticket max age set to 10 hours, service tickets to 600 minutes, renew age to 7 days, max clock skew capped at 5 minutes.
- **Account Lockout Thresholds:** 5 invalid logon attempts triggers a 15-minute lockout with a 15-minute counter reset window.
- **Protocol Hardening:** SMBv1 disabled, LLMNR multicast resolution disabled via registry GPO (`EnableMulticast = 0`), NTLM restricted to NTLMv2 only (`LMCompatibilityLevel = 5`).
- **Advanced Audit Subcategories (`logs/auditpol_policy.txt`):** Explicitly enabled Success and Failure logging for Kerberos Authentication Service (Event ID 4768/4771), Kerberos Service Ticket Operations (Event ID 4769), User & Security Group Management (Event IDs 4720, 4732), and Process Creation (Event ID 4688).

---

## Domain Join Procedure (`Windows-10` Workstation)

1. **DNS Configuration:** Updated IPv4 DNS Server on `Windows-10` (`192.168.56.108`) to point strictly to `192.168.56.10` (`dc01.homelab.local`).
2. **Domain Join Execution:** Joined `homelab.local` domain via PowerShell:
   ```powershell
   Add-Computer -DomainName "homelab.local" -Credential (Get-Credential) -Restart
   ```
3. **Verification:** Verified workstation computer account placement in `DC=homelab,DC=local` and confirmed domain logon capability for `HOMELAB\analyst01`.

---

## Active Directory Network Port Dissection

Verified active AD services on `192.168.56.10`:

```text
Port 53   - AD Integrated DNS Server
Port 88   - Kerberos Key Distribution Center (KDC)
Port 135  - RPC Endpoint Mapper
Port 139  - NetBIOS Session Service
Port 389  - LDAP (Lightweight Directory Access Protocol)
Port 445  - SMB / SYSVOL / Netlogon Shares
Port 464  - Kerberos Change/Set Password
Port 593  - RPC over HTTP
Port 636  - LDAPS (LDAP over SSL)
Port 3268 - Global Catalog
Port 5985 - WinRM (PowerShell Remoting)
```

### Active Directory DNS SRV Query (`logs/dig_srv_query.txt`)
```text
dig SRV _ldap._tcp.dc._msdcs.homelab.local @192.168.56.10
_ldap._tcp.dc._msdcs.homelab.local. 600 IN SRV 0 100 389 dc01.homelab.local.
```

### NetBIOS Enumeration (`logs/netbios_enum.txt`)
```text
DC01     <00> UNIQUE  Workstation / Host Name
HOMELAB  <00> GROUP   Domain / Workgroup Name
HOMELAB  <1C> GROUP   Domain Controller Group
HOMELAB  <1B> UNIQUE  Domain Master Browser
```

---

## Verification & Audit Shell Script (`scripts/verify_ad.sh`)

Execute the shell script to query AD DNS SRV records and verify service ports:
```bash
./scripts/verify_ad.sh
```

---

## Setup & Engineering Notes

- **DNS Dependency**: Windows 10 domain join attempts fail with error `DNS name does not exist` if client IPv4 DNS is set to an external resolver (like `1.1.1.1` or pfSense WAN). The client's primary DNS must be set explicitly to the Domain Controller IP `192.168.56.10`.
- **Clock Synchronization**: Kerberos authentication requires system time alignment within 5 minutes between `DC01` and client workstations. Both VMs are configured to sync RTC to host system time in VirtualBox settings.
- **Audit Policy Precedence**: Advanced Audit Policy subcategories (`auditpol`) override legacy high-level audit categories. When configuring via Secedit / GPO, verify subcategory enablement via `auditpol /get /category:*`.
