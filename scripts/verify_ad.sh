#!/bin/bash
# verify_ad.sh - Verify AD DS DNS SRV Records and Domain Controller reachability
# Target: dc01.homelab.local (192.168.56.10)
# Author: Jacob John

DC_IP="192.168.56.10"
DOMAIN="homelab.local"

echo "=================================================="
echo " Active Directory Domain Verification ($DOMAIN)"
echo "=================================================="

echo ""
echo "[+] 1. Querying SOA Record for $DOMAIN:"
dig SOA $DOMAIN @$DC_IP +short || echo "[!] SOA query failed"

echo ""
echo "[+] 2. Querying LDAP SRV Record (_ldap._tcp.dc._msdcs.$DOMAIN):"
dig SRV _ldap._tcp.dc._msdcs.$DOMAIN @$DC_IP +short || echo "[!] LDAP SRV query failed"

echo ""
echo "[+] 3. Querying Kerberos KDC SRV Record (_kerberos._tcp.dc._msdcs.$DOMAIN):"
dig SRV _kerberos._tcp.dc._msdcs.$DOMAIN @$DC_IP +short || echo "[!] KDC SRV query failed"

echo ""
echo "[+] 4. Checking Active Directory Ports on $DC_IP:"
for port in 53 88 135 389 445 464 3268 5985; do
    (echo >/dev/tcp/$DC_IP/$port) 2>/dev/null && echo "  [+] Port $port OPEN" || echo "  [!] Port $port CLOSED"
done

echo ""
echo "=================================================="
echo "[+] AD Verification Complete."
