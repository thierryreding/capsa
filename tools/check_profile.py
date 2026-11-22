import sys, yaml, collections
d = yaml.safe_load(open(sys.argv[1], encoding="utf-8"))
p = d["profile"]; req = p["required_translation_lang"]
ids = {}; errs = []
for u in d["units"]:
    for e in u["entries"]:
        if e["id"] in ids: errs.append("dup id " + e["id"])
        ids[e["id"]] = u["id"]
        if not e["id"].startswith(u["id"] + "-"): errs.append("prefix " + e["id"])
        if not e.get("tr", {}).get(req): errs.append("no required tr " + e["id"])
        for lang in e.get("tr", {}):
            if lang not in p["translation_langs"]: errs.append("lang " + e["id"])
for u in d["units"]:
    for r in u.get("review", []):
        if r not in ids: errs.append("bad review ref " + r)
        elif int(ids[r][1:]) >= int(u["id"][1:]): errs.append("review not earlier " + r)
print({u["id"]: len(u["entries"]) for u in d["units"]}, "total", len(ids))
print("errors:", errs or "none")
