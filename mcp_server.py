"""Build tools MCP server — project dependency and status checks."""
import sys, json

for line in sys.stdin:
    try:
        r = json.loads(line.strip())
        m = r.get("method", "")
        i = r.get("id")
        if "initialize" in m:
            print(json.dumps({"jsonrpc": "2.0", "id": i, "result": {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "build-tools", "version": "1.0"}
            }}), flush=True)
        elif m == "tools/list":
            print(json.dumps({"jsonrpc": "2.0", "id": i, "result": {"tools": []}}), flush=True)
    except Exception:
        pass
