#!/usr/bin/env python3
"""MCP demo: drives arcus-mcp over stdio JSON-RPC, as Claude would, to build the MCP demo house.

Brief: "A one-storey, two-bedroom cottage, 36' x 28', 9' walls and a 6:12 gable roof. Open living / kitchen / dining
along the south, two bedrooms with a bath between them along the north. Front door on the south, a back door from
the kitchen on the east. Furnish it, dimension and tag the plan, and make a small sheet set."
"""
import json, subprocess, sys, os

# Usage: python3 Tools/MCP/demo_house.py .build/debug/arcus-mcp ~/Documents/Arcus
binary, outdir = sys.argv[1], os.path.expanduser(sys.argv[2])
p = subprocess.Popen([binary, "--mode", "file"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
seq = 0

def rpc(method, params=None):
    global seq
    seq += 1
    p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": seq, "method": method, "params": params or {}}) + "\n")
    p.stdin.flush()
    return json.loads(p.stdout.readline())

def tool(_tool, **args):
    r = rpc("tools/call", {"name": _tool, "arguments": args})
    if "error" in r:
        print(f"!! {_tool}: RPC error {r['error']}"); sys.exit(1)
    res = r["result"]
    text = next(c["text"] for c in res["content"] if c["type"] == "text")
    if res.get("isError"):
        print(f"!! {_tool}: {text}"); sys.exit(1)
    data = json.loads(text)
    shown = json.dumps(data)
    print(f"-> {_tool}: {shown[:600]}{'…' if len(shown) > 600 else ''}")
    return data

init = rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "demo", "version": "1"}})
print("initialize:", init["result"]["serverInfo"], init["result"]["protocolVersion"])
p.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
print("tools:", len(rpc("tools/list")["result"]["tools"]))

tool("arcus_status")
tool("create_project", name="MCP Demo", levels=[{"name": "Floor", "elevation": 0}, {"name": "Roof", "elevation": "9'"}])
tool("set_project_info", number="2026-MCP", client="Owner", address="Demo lot", status="Concept", issue_date="2026-10-19", building_name="Two-Bedroom Cottage")

ext = tool("create_walls", level="Floor", type="Generic - 8\"", points=[[0, 0], [0, 28], [36, 28], [36, 0]], closed=True)
W, N, E, S = [w["id"] for w in ext["walls"]]
part = tool("create_walls", level="Floor", type="Interior - 4 1/2\" Partition (2x4)",
            segments=[[[0, 16], [36, 16]], [[14, 16], [14, 28]], [[21, 16], [21, 28]]])
H, B1, B2 = [w["id"] for w in part["walls"]]

# Offsets run from each wall's start: W (0,0)→(0,28), N (0,28)→(36,28), E (36,28)→(36,0), S (36,0)→(0,0), H (0,16)→(36,16).
tool("place_doors", doors=[
    {"wall": S, "offset": 28, "type": "Single Panel 36x80", "mark": "1"},
    {"wall": E, "offset": 20, "type": "Single Panel 32x80", "mark": "2", "flip_facing": True},
    {"wall": H, "offset": 11, "type": "Single Flush 32x80", "mark": "3", "flip_facing": True},
    {"wall": H, "offset": 17.5, "type": "Single Flush 30x80", "mark": "4", "flip_facing": True},
    {"wall": H, "offset": 24.5, "type": "Single Flush 32x80", "mark": "5", "flip_facing": True},
])
tool("place_windows", windows=[
    {"wall": S, "offset": 18, "type": "Casement Double 72x60", "sill_height": "2'-6\""},
    {"wall": S, "offset": 5, "type": "Casement 36x60", "sill_height": "2'-6\""},
    {"wall": W, "offset": 8, "type": "Casement 36x60", "sill_height": "2'-6\""},
    {"wall": W, "offset": 22, "type": "Casement 36x60", "sill_height": "2'-6\""},
    {"wall": N, "offset": 7, "type": "Casement 36x60", "sill_height": "2'-6\""},
    {"wall": N, "offset": 17.5, "type": "Awning 36x24", "sill_height": "5'"},
    {"wall": N, "offset": 28.5, "type": "Casement 36x60", "sill_height": "2'-6\""},
    {"wall": E, "offset": 6, "type": "Casement 36x60", "sill_height": "2'-6\""},
    {"wall": E, "offset": 13, "type": "Casement 48x24", "sill_height": "4'-6\""},
])
tool("create_floor", level="Floor", from_walls=True, edge="interior", name="Floor Slab")
tool("create_roof", level="Roof", from_walls_of="Floor", shape="gable", slope=26.57, overhang="1'-6\"")
rooms = tool("place_rooms", level="Floor", rooms=[
    {"name": "Living / Kitchen", "point": [18, 8], "number": "101", "floor_finish": "Oak"},
    {"name": "Bedroom 1", "point": [7, 22], "number": "102", "floor_finish": "Oak"},
    {"name": "Bath", "point": [17.5, 22], "number": "103", "floor_finish": "Tile"},
    {"name": "Bedroom 2", "point": [28.5, 22], "number": "104", "floor_finish": "Oak"},
])
tool("create_ceiling", level="Floor", all_rooms=True, height="8'-6\"")
tool("place_components", components=[
    {"family": "Sofa - 3 Seat", "type": "84", "point": [6, 7], "facing": "north"},
    {"family": "Coffee Table - Rectangular", "point": [6, 10]},
    {"family": "Dining Set - 6 Seat", "point": [20, 9.5]},
    {"family": "Refrigerator - French Door", "point": [34.3, 13.6], "facing": "west"},
    {"family": "Range - Freestanding", "type": "30", "point": [34.5, 9.5], "facing": "west"},
    {"family": "Base Cabinet - US", "type": "24", "point": [34.5, 11.5], "facing": "west"},
    {"family": "Bed - US Standard", "type": "Queen", "point": [7, 24.3], "facing": "south"},
    {"family": "Nightstand", "point": [3.6, 27.0], "facing": "south"},
    {"family": "Bed - US Standard", "type": "Full", "point": [28.5, 24.5], "facing": "south"},
    {"family": "Bathtub - Alcove", "type": "60", "point": [17.5, 26.4], "facing": "south"},
    {"family": "WC - Floor Mounted", "point": [15.3, 21.5], "facing": "east"},
    {"family": "Lavatory - Vanity", "type": "24", "point": [20.1, 21.5], "facing": "west"},
])
tool("create_views", views=[
    {"kind": "section", "name": "Section A", "start": [-4, 20], "end": [40, 20], "scale": 48},
    {"kind": "section", "name": "Section B", "start": [10, -4], "end": [10, 32], "scale": 48, "flip": True},
    {"kind": "three_d", "name": "3D - Cutaway", "cut_to_level": "Floor"},
])
tool("add_dimensions", view="Floor", auto=True)
tool("add_tags", view="Floor", categories=["doors", "windows"])
tool("create_schedule", kind="doors")
tool("create_schedule", kind="windows")
tool("create_sheet", number="A101", name="Floor Plan", views=[{"view": "Floor", "position": [0.3, 0.5]}, {"view": "Room Schedule", "position": [0.66, 0.8]}])
tool("create_sheet", number="A201", name="Exterior Elevations", views=[{"view": "South"}, {"view": "North"}, {"view": "East"}, {"view": "West"}])
tool("create_sheet", number="A301", name="Building Sections", views=[{"view": "Section A"}, {"view": "Section B"}])
tool("create_sheet", number="A401", name="3D and Schedules", views=[{"view": "3D - Cutaway", "position": [0.27, 0.62]}, {"view": "Door Schedule", "position": [0.62, 0.72]},
     {"view": "Window Schedule", "position": [0.62, 0.38]}])

tool("query_model", what="rooms")
tool("query_model", what="warnings")
saved = tool("save", path=os.path.join(outdir, "MCP Demo.arcus"))
tool("render_view", view="Floor", path=os.path.join(outdir, "MCP Demo - Floor Plan.png"), width=2400, inline=False)
tool("render_view", view="3D - Cutaway", path=os.path.join(outdir, "MCP Demo - 3D Cutaway.png"), width=1600, inline=False)
tool("render_view", view="A101", path=os.path.join(outdir, "MCP Demo - A101.png"), width=2400, inline=False)
tool("export_pdf", path=os.path.join(outdir, "MCP Demo - Sheets.pdf"))
p.stdin.close()
p.wait(timeout=30)
print("server stderr:", p.stderr.read().strip())
