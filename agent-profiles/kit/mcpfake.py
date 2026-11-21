#!/usr/bin/env python3
"""mcpfake.py: minimal stdio MCP server (JSON-RPC 2.0, newline-delimited) exposing 15 synthetic tools with realistic
schemas, so a "lived-in" install carries the MCP tool weight a real user's would. Calls return a fixed synthetic text.
Python 3.9+, stdlib only."""
import json, sys
DOMAINS = ["notes", "calendar", "tasks", "contacts", "files", "mail", "weather", "news", "finance", "recipes",
           "fitness", "music", "travel", "shopping", "home"]
def tool(d):
    return {"name": f"lab_{d}_query", "description": f"Search, list, create or update {d} items in the synthetic lab {d} "
            f"service. Use for any request about {d}. Returns a JSON list of matching {d} records with ids, titles, "
            f"timestamps and short previews; supports paging and filters.",
            "inputSchema": {"type": "object", "properties": {
                "action": {"type": "string", "enum": ["search", "list", "get", "create", "update", "delete"], "description": f"What to do with {d} items."},
                "query": {"type": "string", "description": "Free-text search terms."},
                "id": {"type": "string", "description": f"The {d} item id, for get/update/delete."},
                "fields": {"type": "object", "description": "Fields to set on create/update.", "additionalProperties": True},
                "limit": {"type": "integer", "minimum": 1, "maximum": 100, "description": "Maximum results."},
                "cursor": {"type": "string", "description": "Paging cursor from a previous call."}},
                "required": ["action"]}}
TOOLS = [tool(d) for d in DOMAINS]
def send(o): sys.stdout.write(json.dumps(o) + "\n"); sys.stdout.flush()
for line in sys.stdin:
    try: m = json.loads(line)
    except Exception: continue
    mid, meth = m.get("id"), m.get("method")
    if meth == "initialize":
        send({"jsonrpc": "2.0", "id": mid, "result": {"protocolVersion": (m.get("params") or {}).get("protocolVersion", "2025-06-18"),
              "capabilities": {"tools": {}}, "serverInfo": {"name": "labtools", "version": "1.0.0"}}})
    elif meth == "tools/list":
        send({"jsonrpc": "2.0", "id": mid, "result": {"tools": TOOLS}})
    elif meth == "tools/call":
        send({"jsonrpc": "2.0", "id": mid, "result": {"content": [{"type": "text", "text": "[]"}], "isError": False}})
    elif meth == "ping":
        send({"jsonrpc": "2.0", "id": mid, "result": {}})
    elif mid is not None:
        send({"jsonrpc": "2.0", "id": mid, "error": {"code": -32601, "message": "method not found"}})
