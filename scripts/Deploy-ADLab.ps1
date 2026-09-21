# Deploy-ADLab.ps1 - Active Directory Domain Services Provisioning Script
# Target: Windows Server 2019 (DC01 - 192.168.56.10)
# Domain: homelab.local (NetBIOS: HOMELAB)
# Author: Jacob John

Import-Module ActiveDirectory

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " Provisioning Active Directory Lab Environment " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Create Organizational Units (OUs)
$OUs = @("OUs_Employees", "OUs_Workstations", "OUs_Servers", "OUs_Groups")
foreach ($OU in $OUs) {
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$OU'")) {
        New-ADOrganizationalUnit -Name $OU -Path "DC=homelab,DC=local" -ProtectedFromAccidentalDeletion $true
        Write-Host "[+] Created OU: $OU" -ForegroundColor Green
    }
}

# 2. Create Security Groups
$Groups = @(
    @{ Name = "Sec_Tier1_SOC"; Path = "OU=OUs_Groups,DC=homelab,DC=local" },
    @{ Name = "Sec_Helpdesk"; Path = "OU=OUs_Groups,DC=homelab,DC=local" }
)

foreach ($G in $Groups) {
    if (-not (Get-ADGroup -Filter "Name -eq '$($G.Name)'")) {
        New-ADGroup -Name $G.Name -GroupScope Global -GroupCategory Security -Path $G.Path
        Write-Host "[+] Created Security Group: $($G.Name)" -ForegroundColor Green
    }
}

# 3. Create Sample Lab Users
$Users = @(
    @{ sAMAccountName = "jadmin"; GivenName = "Jacob"; Surname = "Admin"; Path = "OU=OUs_Employees,DC=homelab,DC=local" },
    @{ sAMAccountName = "analyst01"; GivenName = "SOC"; Surname = "Analyst"; Path = "OU=OUs_Employees,DC=homelab,DC=local" }
)

$Password = ConvertTo-SecureString "P@ssw0rd2026!Sec" -AsPlainText -Force

foreach ($U in $Users) {
    if (-not (Get-ADUser -Filter "sAMAccountName -eq '$($U.sAMAccountName)'")) {
        New-ADUser -sAMAccountName $U.sAMAccountName -GivenName $U.GivenName -Surname $U.Surname `
                   -UserPrincipalName "$($U.sAMAccountName)@homelab.local" -Path $U.Path `
                   -AccountPassword $Password -Enabled $true -PasswordNeverExpires $true
        Write-Host "[+] Created User: $($U.sAMAccountName)" -ForegroundColor Green
    }
}

# 4. Add User to Security Group
Add-ADGroupMember -Identity "Sec_Tier1_SOC" -Members "analyst01" -ErrorAction SilentlyContinue
Write-Host "[+] Added analyst01 to Sec_Tier1_SOC group" -ForegroundColor Green

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "[+] AD Lab Provisioning Complete." -ForegroundColor Cyan
