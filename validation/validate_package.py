from pathlib import Path
import json, hashlib, sys
root=Path(__file__).resolve().parents[1]
files=[p for p in root.rglob('*') if p.is_file() and p.name!='INTEGRITY_SHA256_v3.2.json']
main=(root/'docs/canon/XRAI_ULU_EVREN_COMPLETE_BUILD_CONSTITUTION_v3.2.md').read_bytes()
assert b'# COMPLETE IMMUTABLE v3.1 MASTER' in main
base=main.split('# COMPLETE IMMUTABLE v3.1 MASTER — FULLY PRESERVED BELOW\n\n'.encode('utf-8'),1)[1]
expected=(root/'docs/registries/BASELINE_HASHES_v3.2.json')
assert hashlib.sha256(base).hexdigest()==json.loads(expected.read_text())['v3_1_sha256']
for stem,attr,count in [('ORIGINAL_MATH_METHOD_REGISTRY_v3.2.json','methods',18),('SECURITY_DATA_EGRESS_MATRIX_v3.2.json','flows',15),('EXECUTION_OVERLAY_TASKS_v3.2.json','tasks',18),('NEW_ACCEPTANCE_TESTS_v3.2.json','test_cases',1),('UX_PIXEL_SCREEN_CONTRACTS_v3.2.json','screens',12)]:
 x=json.loads((root/'docs/registries'/stem).read_text()); assert len(x[attr])>=count,(stem,len(x[attr]))
tasks=json.loads((root/'docs/registries/EXECUTION_OVERLAY_TASKS_v3.2.json').read_text())['tasks']; taskids={t['id'] for t in tasks}; assert len(taskids)==len(tasks)
for t in tasks:
 for dep in t['depends_on']:
  assert dep in taskids or dep=='P00-W01',(t['id'],dep)
for x in files:
 if x.suffix=='.json':json.loads(x.read_text())
print(f'PASS spec structure; files={len(files)}; methods={len(json.loads((root/"docs/registries/ORIGINAL_MATH_METHOD_REGISTRY_v3.2.json").read_text())["methods"])}; tests={len(json.loads((root/"docs/registries/NEW_ACCEPTANCE_TESTS_v3.2.json").read_text())["test_cases"])}; tasks={len(tasks)}; v3.1 original preserved SHA256; does NOT verify an iOS build')
