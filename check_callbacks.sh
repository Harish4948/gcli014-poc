#!/usr/bin/env bash
# =============================================================================
# GCLI-014 — Interactsh Callback Monitor
# Polls /tmp/gcli014_interactions.json and highlights GCLI-014 hits
# =============================================================================

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

INTERACTIONS_FILE="/tmp/gcli014_interactions.json"
PAYLOAD_FILE=".gemini/payload_store.txt"
SEEN_FILE="/tmp/gcli014_seen_interactions"
touch "$SEEN_FILE"

if [[ ! -f "$PAYLOAD_FILE" ]]; then
    echo -e "${RED}[!] No payload_store.txt found. Run ./setup.sh first.${NC}"
    exit 1
fi

OAST_HOST=$(cat "$PAYLOAD_FILE" | tr -d '[:space:]')
echo -e "${CYAN}[*] Monitoring callbacks for: ${OAST_HOST}${NC}"
echo -e "${CYAN}[*] Interaction log: ${INTERACTIONS_FILE}${NC}"
echo -e "${YELLOW}[*] Waiting for DNS / HTTP hits... (Ctrl+C to stop)${NC}"
echo ""

print_hit() {
    local protocol="$1"
    local remote_addr="$2"
    local raw_request="$3"
    local timestamp="$4"
    local unique_id="$5"

    # Skip if already shown
    if grep -qF "$unique_id" "$SEEN_FILE" 2>/dev/null; then
        return
    fi
    echo "$unique_id" >> "$SEEN_FILE"

    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  [HIT] GCLI-014 callback received!                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo -e "  Protocol  : ${CYAN}${protocol}${NC}"
    echo -e "  Remote IP : ${CYAN}${remote_addr}${NC}"
    echo -e "  Timestamp : ${CYAN}${timestamp}${NC}"

    if [[ "$protocol" == "http" ]]; then
        # Decode the raw HTTP request to show the callback path
        local decoded
        decoded=$(echo "$raw_request" | python3 -c "
import sys, base64
try:
    data = base64.b64decode(sys.stdin.read().strip()).decode('utf-8', errors='replace')
    lines = data.split('\n')[:5]
    for l in lines:
        print('  ' + l)
except Exception as e:
    print('  (decode error: ' + str(e) + ')')
" 2>/dev/null)
        echo -e "  HTTP Request (first 5 lines):"
        echo -e "${YELLOW}${decoded}${NC}"
    elif [[ "$protocol" == "dns" ]]; then
        echo -e "  ${YELLOW}DNS lookup — Gate 1 confirms process spawned${NC}"
    fi
    echo ""
}

# Summary of what to look for
echo -e "  ${YELLOW}PoC hit path pattern:${NC}  /gcli014/spawn/<id_output>@<hostname>"
echo -e "  ${YELLOW}DNS hit${NC} = server process spawned (Gate 1)"
echo -e "  ${YELLOW}HTTP hit${NC} = curl executed, id output exfilled (Gate 1 + Gate 2)"
echo ""

# Polling loop
while true; do
    if [[ ! -f "$INTERACTIONS_FILE" ]]; then
        sleep 2
        continue
    fi

    # Read each JSON line from the interaction log
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        protocol=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('protocol',''))" 2>/dev/null)
        remote_addr=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('remote-address',''))" 2>/dev/null)
        timestamp=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('timestamp',''))" 2>/dev/null)
        raw_request=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('raw-request','') or d.get('raw-request',''))" 2>/dev/null)
        unique_id=$(echo "$line" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(d.get('unique-id',''))" 2>/dev/null)

        if [[ -n "$protocol" ]]; then
            print_hit "$protocol" "$remote_addr" "$raw_request" "$timestamp" "$unique_id"
        fi
    done < "$INTERACTIONS_FILE"

    sleep 3
done
