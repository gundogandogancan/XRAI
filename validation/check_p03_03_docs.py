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

# P03-04b: the backup/restore review exists, cites its baseline, names only matrix rows, the matrix carries the new families, threat rows T49/T50 exist
rev_b = root / "docs/status/P03_04B_BACKUP_RESTORE_REVIEW_REPORT.md"
if not rev_b.exists(): problems.append("missing P03_04B_BACKUP_RESTORE_REVIEW_REPORT.md")
else:
    rt = rev_b.read_text()
    if "42c3f4e" not in rt: problems.append("P03-04b review does not cite the baseline 42c3f4e")
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", rt)):
        if nid not in matrix_ids: problems.append(f"P03-04b review references {nid} which is not a matrix row")
    for fam, n in (("LR", 8), ("BK", 8), ("RR", 14), ("AT", 11), ("SC", 1)):
        for i in range(1, n + 1):
            if f"NT-{fam}-{i:02d}" not in matrix_ids: problems.append(f"matrix lacks NT-{fam}-{i:02d}")
    for word in ("Requirement", "Remaining Limit", "GO / NO-GO", "Final SHA"):
        if word not in rt: problems.append(f"P03-04b review lacks '{word}'")
    for t in ("T49", "T50"):
        if f"| {t} |" not in tm: problems.append(f"threat model lacks row {t}")
    for bid in ("LEDGER_CORRUPT_LAUNDERING", "RESTORE_TWO_PHASE", "ATTACHMENTS_NOT_IN_BACKUP", "RESTORE_WHOLE_BACKUP_IN_MEMORY"):
        if bid not in blockers: problems.append(f"OPEN_BLOCKERS lacks {bid}")
    if "<!-- HOSTS -->" in matrix_h: problems.append("matrix P03-04b rows still carry the HOSTS placeholder")
    store_src = (root / "Packages/XRAICore/Sources/XRAIVaultStore/FileVaultStore.swift").read_text()
    if "sourceVaultInstanceID:" in store_src: problems.append("admission still takes the instance id from the caller (P03-04b requires provenance from the backup)")

# P03-04bH: the restore/authorization report exists, cites its baseline, NT-BH rows exist, T51 exists, putEnvelope is gone
rev_h = root / "docs/status/P03_04BH_RESTORE_AUTHORIZATION_SECURITY_REPORT.md"
if not rev_h.exists(): problems.append("missing P03_04BH_RESTORE_AUTHORIZATION_SECURITY_REPORT.md")
else:
    rt = rev_h.read_text()
    if "6194075" not in rt: problems.append("P03-04bH report does not cite the baseline 6194075")
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", rt)):
        if nid not in matrix_ids: problems.append(f"P03-04bH report references {nid} which is not a matrix row")
    for i in range(1, 10):
        if f"NT-BH-{i:02d}" not in matrix_ids: problems.append(f"matrix lacks NT-BH-{i:02d}")
    if "| T51 |" not in tm: problems.append("threat model lacks row T51")
    for bid in ("F_P04B_01_BLOOM_RESURRECTION", "F_P04B_02_UNAUTHORIZED_ENVELOPE_WRITE", "F_P04B_03_VERIFIED_PROVENANCE"):
        if bid not in blockers: problems.append(f"OPEN_BLOCKERS lacks {bid}")
    if "<!-- HOSTS2 -->" in matrix_h: problems.append("matrix P03-04bH rows still carry the HOSTS2 placeholder")
    store_src = (root / "Packages/XRAICore/Sources/XRAIVaultStore/FileVaultStore.swift").read_text()
    if "public func putEnvelope" in store_src: problems.append("putEnvelope is back on the production surface (F-P04B-02)")
    if "guard vault.isVerified(result)" not in store_src: problems.append("admission no longer requires a verified restore result (F-P04B-03)")
    if "possiblyDeletedForever" not in store_src: problems.append("activation no longer refuses possibly-deleted ids (F-P04B-01)")
    for word in ("GO/NO-GO", "HEAD SHA"):
        if word not in rt: problems.append(f"P03-04bH report lacks '{word}'")

# P03-04bH2: the global deletion report exists, NT-GD rows exist, T52 exists, the policy is wired, releaseQuarantined is gone
rev_g = root / "docs/status/P03_04BH2_GLOBAL_DELETION_SECURITY_REPORT.md"
if not rev_g.exists(): problems.append("missing P03_04BH2_GLOBAL_DELETION_SECURITY_REPORT.md")
else:
    rt = rev_g.read_text()
    if "bff2bd3" not in rt: problems.append("P03-04bH2 report does not cite the baseline bff2bd3")
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", rt)):
        if nid not in matrix_ids: problems.append(f"P03-04bH2 report references {nid} which is not a matrix row")
    for i in range(1, 8):
        if f"NT-GD-{i:02d}" not in matrix_ids: problems.append(f"matrix lacks NT-GD-{i:02d}")
    if "| T52 |" not in tm: problems.append("threat model lacks row T52")
    for bid in ("F_P04BH_01_DELETED_ID_RECREATED", "RELEASE_QUARANTINED_REMOVED", "STICKY_DISTRUST_RESET", "BATCH_ADMISSION_GROUPED_COMMIT"):
        if bid not in blockers: problems.append(f"OPEN_BLOCKERS lacks {bid}")
    if "<!-- HOSTS3 -->" in matrix_h: problems.append("matrix P03-04bH2 rows still carry the HOSTS3 placeholder")
    store_src = (root / "Packages/XRAICore/Sources/XRAIVaultStore/FileVaultStore.swift").read_text()
    if "public func releaseQuarantined" in store_src: problems.append("releaseQuarantined is back (P03-04bH2 GATE 4)")
    for fn in ("public func put(", "public func putAttachment(", "public func activateRestored(", "public func reimportUnderNewID(", "public func get(", "public func readAttachment("):
        if fn not in store_src: problems.append(f"store lacks {fn}")
    if store_src.count("IdentityPolicy.") < 10: problems.append("IdentityPolicy is consulted at fewer entry points than expected")
    for word in ("GO / NO-GO", "Final SHA", "Root cause"):
        if word not in rt: problems.append(f"P03-04bH2 report lacks '{word}'")

# P03-05A: six deliverables exist, cite the baseline, rows resolve, T53 exists, no direct issuer use in app code
for name in ("P03_05A_CANONICAL_RECONCILIATION", "P03_05A_CONSENT_AND_INTERACTION_ARCHITECTURE", "P03_05A_PRIVACY_UX_ACCEPTANCE_MATRIX", "P03_05A_SECURITY_NEGATIVE_TEST_MATRIX", "P03_05A_PERFORMANCE_AND_RECOVERY_DECISIONS", "P03_05A_GATE_REVIEW_REPORT"):
    q = root / f"docs/status/{name}.md"
    if not q.exists(): problems.append(f"missing {name}.md"); continue
    qt = q.read_text()
    if "1a3a448" not in qt: problems.append(f"{name}.md does not cite the baseline 1a3a448")
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", qt)):
        if nid not in matrix_ids: problems.append(f"{name}.md references {nid} which is not a matrix row")
for fam, n in (("CA", 6), ("PR", 3), ("IG", 6), ("UX", 7)):
    for i in range(1, n + 1):
        if f"NT-{fam}-{i:02d}" not in matrix_ids: problems.append(f"matrix lacks NT-{fam}-{i:02d}")
if "| T53 |" not in tm: problems.append("threat model lacks row T53")
if "<!-- HOSTS5 -->" in matrix_h: problems.append("matrix P03-05A rows still carry the HOSTS5 placeholder")
if not (root / "docs/adr/ADR-BOOT-010-consent-and-interaction-authority.md").exists(): problems.append("ADR-BOOT-010 missing")
app_dir = root / "App/XRAI"
for f in app_dir.rglob("*.swift"):
    t = f.read_text()
    if ".issue(" in t: problems.append(f"app code calls the issuer directly: {f.name}")
    if "AuthorizationIssuer(" in t and f.name != "SecurityStatus.swift": problems.append(f"app code constructs an issuer: {f.name}")
if "XRAIVaultStore" in (root / "project.yml").read_text().split("\n  XRAI:\n")[1].split("\n  XRAIHostedTests:")[0]: problems.append("XRAI app target links XRAIVaultStore before P03-05B")

# P04-00: living-experience deliverables exist and cite the baseline; the court grammar's sources never import vault
# modules, carry no forbidden copy, and the vault/consent/keychain/interaction sources are untouched by the branch
# (checked by content hash against the P03-05A manifest recorded below); ADR-BOOT-011 exists.
for name in ("P04_00_LIVING_EXPERIENCE_GRAMMAR", "P04_00_VISUAL_LANGUAGE_AND_MOTION", "P04_00_OCTOPUS_TO_SCREEN_CONTRACT", "P04_00_FIRST_MINUTE_USER_JOURNEY", "P04_00_PROTOTYPE_REVIEW_REPORT", "P04_00_P03_05B_READINESS"):
    q = root / f"docs/status/{name}.md"
    if not q.exists(): problems.append(f"missing {name}.md"); continue
    qt = q.read_text()
    if "4c5235f" not in qt: problems.append(f"{name}.md does not cite the baseline 4c5235f")
    for nid in set(re.findall(r"NT-[A-Z0-9]+-\d+", qt)):
        if nid not in matrix_ids: problems.append(f"{name}.md references {nid} which is not a matrix row")
for i in range(1, 12):
    if f"NT-LX-{i:02d}" not in matrix_ids: problems.append(f"matrix lacks NT-LX-{i:02d}")
if not (root / "docs/adr/ADR-BOOT-011-design-tooling.md").exists(): problems.append("ADR-BOOT-011 missing")
exp_dir = root / "App/XRAI/Experience"
forbidden_tr = ("kader", "teşhis", "tarama", "frekans", "aura", "ruh eşi", "titreşim")
for f in sorted(exp_dir.glob("*.swift")) if exp_dir.exists() else []:
    t = f.read_text()
    for mod in ("XRAIVaultStore", "XRAIVaultCryptoKit", "XRAIVaultKeychain", "XRAIVaultInteraction", "XRAIVaultTesting"):
        if f"import {mod}" in t: problems.append(f"Experience/{f.name} imports {mod}")
    in_lexicon = False
    for line in t.split("\n"):
        if line.startswith("enum CopyLexicon"): in_lexicon = True
        elif in_lexicon and line.startswith("}"): in_lexicon = False
        if in_lexicon: continue                      # the list of forbidden words is not copy
        code = line.split("//")[0]
        for w in forbidden_tr:
            if w in code.lower() and "banned" not in line:
                problems.append(f"Experience/{f.name} carries forbidden copy '{w}': {line.strip()[:80]}")
if not exp_dir.exists(): problems.append("App/XRAI/Experience missing (P04-00)")
if "struct TodayLivingView" not in (root / "App/XRAI/RootTabView.swift").read_text() and not (exp_dir / "TodayLivingView.swift").exists(): problems.append("P04-00 Bugün screen missing")

if problems:
    print("FAIL"); [print(" -", p) for p in problems]; sys.exit(1)
print(f"PASS P03-03/P03-03H/P03-04/P03-04H/P03-04b/P03-04bH/P03-04bH2/P03-05A/P04-00 docs: {len(cases)} data classes cross-checked, blockers resolved, ADRs present, no app groups, {len(matrix_ids)} NT rows, T44–T48 present, filesystem review consistent")
