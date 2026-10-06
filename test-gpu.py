import json,subprocess,random,time
from pathlib import Path
import os
os.chdir(Path(__file__).resolve().parent)
r=random.Random(20261006)
gpu=subprocess.Popen(['bin/noid-metal'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
cpu=subprocess.Popen(['oracle/target/release/noid-metal-oracle'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
reports=[]
try:
    for case,base,prefix in [(0,0,0),(1,2**32-4,0x000200003ec4a0),(2,2**63,2**64-1),(3,2**64-65,1234)]:
        header=bytes(r.randrange(256) for _ in range(256)) if case else bytes(256)
        request={'header':header.hex(),'count':64,'base':str(base),'prefix':str(prefix),'digests':True}
        cpu.stdin.write(json.dumps({'header':header.hex(),'prepare':True})+'\n');cpu.stdin.flush()
        prepared=json.loads(cpu.stdout.readline())
        request.update(prepared)
        for process in (cpu,gpu):
            process.stdin.write(json.dumps(request)+'\n');process.stdin.flush()
        expected=json.loads(cpu.stdout.readline())['digests']
        actual=json.loads(gpu.stdout.readline())
        assert actual['digests']==expected,f'CPU/GPU disagreement in case {case}'
        # Exercise GPU target comparison, compact candidate output and strict equality.
        candidate_request={**request,'digests':False,'target':expected[17]}
        for process in (cpu,gpu):
            process.stdin.write(json.dumps(candidate_request)+'\n');process.stdin.flush()
        cpu_nonces=json.loads(cpu.stdout.readline())['nonces']
        gpu_nonces=json.loads(gpu.stdout.readline())['nonces']
        assert set(cpu_nonces)==set(gpu_nonces),f'target comparison mismatch {case}'
        assert str(base+17) not in gpu_nonces, 'equality must not qualify as a share'
        reports.append({'case':case,'hashes':64,'seconds':actual['seconds'],'hashrate':actual['hashrate'],'matched':True})
        print(json.dumps(reports[-1]),flush=True)
    request.update(count=65536,digests=False,target='ff'*32,base='0')
    gpu.stdin.write(json.dumps(request)+'\n');gpu.stdin.flush()
    actual=json.loads(gpu.stdout.readline());assert len(actual['nonces'])==65536
    print(json.dumps({'benchmark':actual['hashrate'],'seconds':actual['seconds']}),flush=True)
    Path('gpu-validation.json').write_text(json.dumps({'matched_hashes':256,'cases':reports,'benchmark_hps':actual['hashrate'],'benchmark_seconds':actual['seconds']},indent=2))
finally:
    for p in (cpu,gpu):
        p.stdin.close();p.wait(timeout=10)
