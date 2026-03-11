#!/usr/bin/env bash
# Check a domain against DNS-based blacklists
# Usage: bash check-blacklists.sh domain.com
# Returns JSON with results

set -euo pipefail

DOMAIN="${1:?Usage: check-blacklists.sh domain.com}"

# Resolve domain to IP (needed for IP-based lists)
IP=$(dig +short "$DOMAIN" A 2>/dev/null | head -1 || true)

# Reverse the IP for DNSBL lookups
REVERSED=""
if [[ -n "$IP" && "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  IFS='.' read -r a b c d <<< "$IP"
  REVERSED="${d}.${c}.${b}.${a}"
fi

# Check a single DNSBL, print "LISTED" or "CLEAN"
check_dnsbl() {
  local query="$1"
  local result
  result=$(dig +short "$query" A 2>/dev/null | head -1 || true)
  if [[ -n "$result" && "$result" =~ ^127\. ]]; then
    echo "LISTED"
  else
    echo "CLEAN"
  fi
}

# Domain-based blacklists
R_SURBL=$(check_dnsbl "${DOMAIN}.multi.surbl.org")
R_URIBL=$(check_dnsbl "${DOMAIN}.multi.uribl.com")
R_SPAMHAUS_DBL=$(check_dnsbl "${DOMAIN}.dbl.spamhaus.org")
R_URIBL_BLACK=$(check_dnsbl "${DOMAIN}.black.uribl.com")

# IP-based blacklists
if [[ -n "$REVERSED" ]]; then
  R_SPAMHAUS_ZEN=$(check_dnsbl "${REVERSED}.zen.spamhaus.org")
  R_SPAMCOP=$(check_dnsbl "${REVERSED}.bl.spamcop.net")
  R_BARRACUDA=$(check_dnsbl "${REVERSED}.b.barracudacentral.org")
else
  R_SPAMHAUS_ZEN="NO_IP"
  R_SPAMCOP="NO_IP"
  R_BARRACUDA="NO_IP"
fi

# Known GoDaddy parking IPs (shared hosting - IP-based lists give false positives)
GODADDY_PARKING_IPS="13.248.213.45 76.223.67.189 184.168.131.241 50.63.202.42 34.102.136.180"
IS_PARKING_IP=false
for pip in $GODADDY_PARKING_IPS; do
  if [[ "$IP" == "$pip" ]]; then IS_PARKING_IP=true; break; fi
done

# Count results - separate domain-level (reliable) from IP-level (unreliable for parked domains)
DOMAIN_LISTED=0
IP_LISTED=0
LISTS_HIT=""

# Domain-based lists (reliable regardless of parking)
for result_pair in "SURBL:$R_SURBL" "Spamhaus_DBL:$R_SPAMHAUS_DBL"; do
  name="${result_pair%%:*}"
  value="${result_pair#*:}"
  if [[ "$value" == "LISTED" ]]; then
    DOMAIN_LISTED=$((DOMAIN_LISTED + 1))
    LISTS_HIT="${LISTS_HIT}${LISTS_HIT:+, }${name}"
  fi
done

# URIBL - often flags parked/expired domains, only count if NOT on a parking IP
for result_pair in "URIBL:$R_URIBL" "URIBL_BLACK:$R_URIBL_BLACK"; do
  name="${result_pair%%:*}"
  value="${result_pair#*:}"
  if [[ "$value" == "LISTED" ]]; then
    if [[ "$IS_PARKING_IP" == "true" ]]; then
      # Likely false positive from parking, note but don't count as real hit
      LISTS_HIT="${LISTS_HIT}${LISTS_HIT:+, }${name}(parking-fp)"
    else
      DOMAIN_LISTED=$((DOMAIN_LISTED + 1))
      LISTS_HIT="${LISTS_HIT}${LISTS_HIT:+, }${name}"
    fi
  fi
done

# IP-based lists (unreliable for parked domains on shared IPs)
for result_pair in "Spamhaus_ZEN:$R_SPAMHAUS_ZEN" "SpamCop:$R_SPAMCOP" "Barracuda:$R_BARRACUDA"; do
  name="${result_pair%%:*}"
  value="${result_pair#*:}"
  if [[ "$value" == "LISTED" ]]; then
    if [[ "$IS_PARKING_IP" == "true" ]]; then
      LISTS_HIT="${LISTS_HIT}${LISTS_HIT:+, }${name}(shared-ip)"
    else
      IP_LISTED=$((IP_LISTED + 1))
      LISTS_HIT="${LISTS_HIT}${LISTS_HIT:+, }${name}"
    fi
  fi
done

LISTED_COUNT=$((DOMAIN_LISTED + IP_LISTED))
CLEAN_COUNT=$((7 - LISTED_COUNT))

# Status based on DOMAIN-level lists only (reliable signal)
if [[ $DOMAIN_LISTED -gt 0 ]]; then
  STATUS="BLACKLISTED"
elif [[ $IP_LISTED -gt 0 && "$IS_PARKING_IP" == "false" ]]; then
  STATUS="SUSPECT"
else
  STATUS="CLEAN"
fi

cat <<EOF
{
  "domain": "${DOMAIN}",
  "ip": "${IP:-none}",
  "is_parking_ip": ${IS_PARKING_IP},
  "status": "${STATUS}",
  "domain_listed": ${DOMAIN_LISTED},
  "ip_listed": ${IP_LISTED},
  "lists_hit": "${LISTS_HIT}",
  "details": {
    "SURBL": "${R_SURBL}",
    "URIBL": "${R_URIBL}",
    "URIBL_BLACK": "${R_URIBL_BLACK}",
    "Spamhaus_DBL": "${R_SPAMHAUS_DBL}",
    "Spamhaus_ZEN": "${R_SPAMHAUS_ZEN}",
    "SpamCop": "${R_SPAMCOP}",
    "Barracuda": "${R_BARRACUDA}"
  }
}
EOF
