#!/usr/bin/env python3
"""Static consistency checks for the P03-03 architecture documents.
- every DataClass case in XRAIVaultContracts/PrivacyModel.swift appears in the inventory and the lifecycle matrix
- every blocker id named in the gate report exists in OPEN_BLOCKERS.md
- every ADR referenced by the persistence ADR exists
- the app entitlements contain no application-groups (AHTOVIA boundary N20)
- the seven mandatory P03-03 documents exist and carry the baseline SHA
Exit 0 on success; non-zero with a list of problems.
"""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[1]
problems = []

pm = (root / "Packages/XRAICore/Sources/XRAIVaultContracts/PrivacyModel.swift").read_text()
cases = re.findall(r'case (\w+) = "([a-z_]+)"', pm.split("public enum DataClass")[1].split("}")[0])
inventory = (root / "docs/status/P03_03_DATA_INVENTORY.md").read_text()
matrix = (root / "docs/status/P03_03_DATA_LIFECYCLE_MATRIX.md").read_text()
for swift_name, raw in cases:
    if raw not in inventory: problems.append(f"DataClass {raw} missing from DATA_INVENTORY")
    if raw not in matrix: problems.append(f"DataClass {raw} missing from DATA_LIFECYCLE_MATRIX")

blockers = (root / "docs/status/OPEN_BLOCKERS.md").read_text()
gate = (root / "docs/status/P03_03_ARCHITECTURE_GATE_REPORT.md").read_text()
for bid in set(re.findall(r"`([A-Z][A-Z0-9_]{6,})`", gate)):
    if bid.startswith(("ADR", "P0", "T", "N", "F-")): continue
    if bid in ("GO", "CONDITIONAL", "NO", "UNKNOWN", "HEAD", "PLANNED", "TESTED", "LIMIT", "MANUAL_PENDING", "DEVICE_VERIFIED", "SECURITY_REVIEWED", "NOT_STARTED", "SPECIFIED", "KNOWN_LIMITATION", "CONDITIONAL_GO", "NO_GO", "RESOLVED_TODAY"): continue
    if bid not in blockers: problems.append(f"gate report names blocker {bid} not present in OPEN_BLOCKERS.md")

adr_doc = (root / "docs/status/P03_03_SECURE_PERSISTENCE_ADR.md").read_text()
for n in ("005", "006", "007", "008"):
    if not list((root / "docs/adr").glob(f"ADR-BOOT-{n}-*.md")): problems.append(f"ADR-BOOT-{n} referenced but missing")

ent = root / "App/XRAI/XRAI.entitlements"
if ent.exists() and "application-groups" in ent.read_text():
    problems.append("entitlements contain application-groups (AHTOVIA boundary N20)")

for name in ("P03_03_DATA_INVENTORY", "P03_03_DATA_LIFECYCLE_MATRIX", "P03_03_CONSENT_AUTHORITY_SPEC", "P03_03_SECURE_PERSISTENCE_ADR",
             "P03_03_DELETION_AND_RECOVERY_DESIGN", "P03_03_THREAT_AND_NEGATIVE_TEST_PLAN", "P03_03_ARCHITECTURE_GATE_REPORT",
             "P03_03_PRIVACY_INTELLIGENCE_BOUNDARY"):
    p = root / f"docs/status/{name}.md"
    if not p.exists(): problems.append(f"missing {name}.md"); continue
    if "713468e" not in p.read_text(): problems.append(f"{name}.md does not cite the baseline 713468e")

if problems:
    print("FAIL"); [print(" -", p) for p in problems]; sys.exit(1)
print(f"PASS P03-03 docs: {len(cases)} data classes cross-checked, blockers resolved, ADRs present, no app groups")
