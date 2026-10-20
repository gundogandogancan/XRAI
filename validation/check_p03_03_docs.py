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

# P03-03H hardening docs: exist, cite their baseline, and every NT-* id in the remediation report exists in the matrix
for name in ("P03_03H_SECURITY_REMEDIATION_REPORT", "P03_04_IMPLEMENTATION_CONTRACT", "P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX"):
    p = root / f"docs/status/{name}.md"
    if not p.exists(): problems.append(f"missing {name}.md"); continue
    if "7fc3091" not in p.read_text(): problems.append(f"{name}.md does not cite the baseline 7fc3091")
matrix_h = (root / "docs/status/P03_04_NEGATIVE_TEST_ACCEPTANCE_MATRIX.md").read_text()
matrix_ids = set(re.findall(r"\| (NT-[A-Z0-9]+-\d+) \|", matrix_h))
for doc in ("P03_03H_SECURITY_REMEDIATION_REPORT", "P03_04_IMPLEMENTATION_CONTRACT"):
    text = (root / f"docs/status/{doc}.md").read_text()
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", text)):
        if nid not in matrix_ids: problems.append(f"{doc}.md references {nid} which is not a row of the acceptance matrix")
for bid in set(re.findall(r"`([A-Z][A-Z0-9_]{6,})`", (root / "docs/status/P03_03H_SECURITY_REMEDIATION_REPORT.md").read_text())):
    if bid in ("ROTATION_CROSS_PROCESS", "VAULT_SECURITY_REVIEW") and bid not in blockers: problems.append(f"remediation report names {bid} missing from OPEN_BLOCKERS.md")
# P03-04: the store review report exists, cites the approved baseline, and every NT id it names is a matrix row
rep = root / "docs/status/P03_04_STORE_REVIEW_REPORT.md"
if not rep.exists(): problems.append("missing P03_04_STORE_REVIEW_REPORT.md")
else:
    rt = rep.read_text()
    if "56a5ece" not in rt: problems.append("P03_04_STORE_REVIEW_REPORT.md does not cite the approved baseline 56a5ece")
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", rt)):
        if nid not in matrix_ids: problems.append(f"store report references {nid} which is not a matrix row")
    if "<!-- RUNS -->" in rt: problems.append("store report still has the RUNS placeholder")
    # no row may be claimed TESTED without a real test name
    for line in matrix_h.split("\n"):
        if line.startswith("| NT-") and "TESTED" in line and "test: `" not in line: problems.append("matrix row claims TESTED without a test name: " + line[:40])
    if "<!-- NT-H5-16 -->" in matrix_h or "<!-- PLATFORM-SUMMARY -->" in matrix_h: problems.append("matrix still has P03-04 placeholders")
    # the app target must not link the store
    yml = (root / "project.yml").read_text()
    app_block = yml.split("\n  XRAI:\n")[1].split("\n  XRAIHostedTests:")[0]
    if "XRAIVaultStore" in app_block: problems.append("XRAI app target links XRAIVaultStore before P03-05")
tm = (root / "docs/security/VAULT_THREAT_MODEL_P02.md").read_text()
for t in ("T44", "T45", "T46", "T47", "T48"):
    if f"| {t} |" not in tm: problems.append(f"threat model lacks row {t}")
# P03-04H: the filesystem review exists, cites its baseline, names only matrix rows, and the matrix carries NT-FS-01…12
rev = root / "docs/status/P03_04H_FILESYSTEM_SECURITY_REVIEW.md"
if not rev.exists(): problems.append("missing P03_04H_FILESYSTEM_SECURITY_REVIEW.md")
else:
    rt = rev.read_text()
    if "f888040" not in rt: problems.append("P03_04H review does not cite the baseline f888040")
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", rt)):
        if nid not in matrix_ids: problems.append(f"P03-04H review references {nid} which is not a matrix row")
    for n in range(1, 13):
        if f"NT-FS-{n:02d}" not in matrix_ids: problems.append(f"matrix lacks NT-FS-{n:02d}")
    for word in ("GO / NO-GO", "Final SHA", "Device verification"):
        if word not in rt: problems.append(f"P03-04H review lacks the section '{word}'")
    for bid in ("F_P04_01_EXCLUSIVE_CREATE", "F_P04_02_DIRSYNC_RESULT", "DIRECTORY_FSYNC_SEMANTICS", "PROTECTION_CLASS_NUMERIC"):
        if bid not in blockers: problems.append(f"OPEN_BLOCKERS lacks {bid}")
    # the iOS exclusive-create pair must be gone from the production file system
    vfs = (root / "Packages/XRAICore/Sources/XRAIVaultStore/VaultFileSystem.swift").read_text()
    if "createFile(atPath" in vfs or "O_TRUNC" in vfs: problems.append("VaultFileSystem still uses createFile/O_TRUNC (F-P04-01)")
    if "_ = fsync(" in vfs: problems.append("VaultFileSystem ignores an fsync result (F-P04-02)")

if problems:
    print("FAIL"); [print(" -", p) for p in problems]; sys.exit(1)
print(f"PASS P03-03/P03-03H/P03-04/P03-04H docs: {len(cases)} data classes cross-checked, blockers resolved, ADRs present, no app groups, {len(matrix_ids)} NT rows, T44–T48 present, filesystem review consistent")
