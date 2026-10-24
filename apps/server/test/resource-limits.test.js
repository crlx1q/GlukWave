import test from 'node:test';
import assert from 'node:assert/strict';
import {readResourceLimits} from '../src/resources.js';

const fixture=entries=>async path=>{if(!(path in entries))throw Error('not mounted');return entries[path];};
test('resource diagnostics distinguish the real container budget from the application heap and host',async()=>{
  const limits=await readResourceLimits(fixture({'/sys/fs/cgroup/cpu.max':'100000 100000','/sys/fs/cgroup/memory.max':'4294967296','/sys/fs/cgroup/memory.current':'536870912','/sys/fs/cgroup/pids.max':'256'}));
  assert.equal(limits.scope,'container');assert.equal(limits.cpuCores,1);assert.equal(limits.memoryMB,4096);assert.equal(limits.containerMemoryMB,512);assert.equal(limits.pidsMax,256);assert(limits.heapLimitMB>0);
  const unlimited=await readResourceLimits(fixture({'/sys/fs/cgroup/cpu.max':'max 100000','/sys/fs/cgroup/memory.max':'max','/sys/fs/cgroup/pids.max':'max'}));assert.equal(unlimited.scope,'unrestricted');assert.equal(unlimited.cpuCores,null);assert.equal(unlimited.memoryMB,null);
  const host=await readResourceLimits(fixture({}));assert.equal(host.scope,'unrestricted');assert.equal(host.containerMemoryMB,null);
});
test('older cgroup mounts preserve fractional CPU quotas without reporting unlimited sentinel memory',async()=>{
  const limits=await readResourceLimits(fixture({'/sys/fs/cgroup/cpu/cpu.cfs_quota_us':'50000','/sys/fs/cgroup/cpu/cpu.cfs_period_us':'100000','/sys/fs/cgroup/memory/memory.limit_in_bytes':'9223372036854771712','/sys/fs/cgroup/memory/memory.usage_in_bytes':'268435456'}));
  assert.equal(limits.cpuCores,0.5);assert.equal(limits.memoryMB,null);assert.equal(limits.containerMemoryMB,256);
});
test('systemd service slice cgroup paths are resolved from /proc/self/cgroup',async()=>{
  const limits=await readResourceLimits(fixture({
    '/proc/self/cgroup':'0::/system.slice/glukwave.service\n',
    '/sys/fs/cgroup/cpu.max':'max 100000',
    '/sys/fs/cgroup/memory.max':'max',
    '/sys/fs/cgroup/system.slice/glukwave.service/cpu.max':'100000 100000',
    '/sys/fs/cgroup/system.slice/glukwave.service/memory.max':'1610612736',
    '/sys/fs/cgroup/system.slice/glukwave.service/memory.current':'268435456',
    '/sys/fs/cgroup/system.slice/glukwave.service/pids.max':'1000',
    '/sys/fs/cgroup/system.slice/glukwave.service/cpu.stat':'usage_usec 5000000\n'
  }));
  assert.equal(limits.scope,'container');
  assert.equal(limits.cpuCores,1);
  assert.equal(limits.memoryMB,1536);
  assert.equal(limits.containerMemoryMB,256);
  assert.equal(limits.pidsMax,1000);
  assert.equal(limits.containerCpuUsageMicros,5000000);
});
