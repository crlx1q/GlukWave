import fs from 'node:fs/promises';
import path from 'node:path';
import crypto from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';

// Country-only PDDL data. Requests download a public database, never visitor IPs.
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),directory=path.join(root,'apps/server/data/geoip');
const origin='https://github.com/sapics/ip-location-db/releases/download';
async function read(url){const response=await fetch(url,{signal:AbortSignal.timeout(60000)});if(!response.ok)throw new Error(`Country database download failed (${response.status})`);const declared=Number(response.headers.get('content-length'));if(declared>100*1024*1024)throw new Error('Country database too large');const parts=[];let bytes=0;for await(const part of response.body){bytes+=part.length;if(bytes>100*1024*1024)throw new Error('Country database too large');parts.push(part);}return Buffer.concat(parts);}
await fs.mkdir(directory,{recursive:true});
const generation=`glukwave-${Date.now()}`,metadata={source:'sapics/ip-location-db user-country',license:'PDDL-1.0',retrievedAt:new Date().toISOString(),databases:{}},completed=[];
for(const family of [4,6]){
  const filename=`user-country-ipv${family}-num.csv`,url=`${origin}/latest/${filename}?v=${generation}`;
  const body=await read(url),checksumText=(await read(`${origin}/checksum/${filename}.sha256?v=${generation}`)).toString('utf8');
  const expected=checksumText.match(/\b[a-f0-9]{64}\b/i)?.[0]?.toLowerCase(),actual=crypto.createHash('sha256').update(body).digest('hex');
  if(!expected||actual!==expected)throw new Error(`Country database checksum mismatch (IPv${family})`);
  const rows=body.toString('utf8').split(/\r?\n/).filter(Boolean).map(line=>{const [start,end,country]=line.split(',');if(!/^\d+$/.test(start)||!/^\d+$/.test(end)||!/^[A-Z]{2}$/.test(country)||BigInt(start)>BigInt(end))throw new Error('Invalid country database');return {start:BigInt(start),end:BigInt(end),country};});
  rows.sort((a,b)=>a.start<b.start?-1:a.start>b.start?1:0);let last=-1n;
  for(const row of rows){if(row.start<=last)throw new Error('Overlapping country ranges');last=row.end;}
  const packed=gzipSync(rows.map(row=>`${row.start},${row.end},${row.country}`).join('\n'),{level:9}),destination=path.join(directory,`ipv${family}.csv.gz`),temporary=destination+'.tmp';
  completed.push({temporary,destination,packed});
  metadata.databases[`ipv${family}`]={url:url.split('?')[0],sourceSha256:actual,packedSha256:crypto.createHash('sha256').update(packed).digest('hex'),rows:rows.length,bytes:packed.length};
  console.log(`IPv${family}: ${rows.length} country ranges verified (${packed.length} compressed bytes).`);
}
// A network/checksum failure leaves the installed databases intact.
for(const file of completed)await fs.writeFile(file.temporary,file.packed);
for(const file of completed)await fs.rename(file.temporary,file.destination);
await fs.writeFile(path.join(directory,'provenance.json'),JSON.stringify(metadata,null,2)+'\n');
