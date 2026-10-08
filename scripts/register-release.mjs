import fs from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),directory=path.join(root,'outputs');
const [platform,filename,version,signature='release',channel=signature==='debug'?'beta':'stable']=process.argv.slice(2);
const extensions={android:['.apk'],windows:['.exe','.zip'],ios:['.ipa']};
if(!Object.hasOwn(extensions,platform)||!filename||filename!==path.basename(filename)||/[\\/:]/.test(filename)||!extensions[platform].includes(path.extname(filename))||!/^\d+\.\d+\.\d+(?:[-+][\w.-]+)?$/.test(version||'')||!['debug','release'].includes(signature)||!['beta','stable'].includes(channel))throw new Error('Usage: node scripts/register-release.mjs android Package.apk 1.0.0 debug beta');
const target=path.join(directory,filename),actual=await fs.realpath(target);if(actual!==target)throw new Error('Release must be an ordinary file inside outputs.');
const stat=await fs.stat(actual);if(!stat.isFile()||stat.size<1)throw new Error('Empty or missing package.');
const hash=crypto.createHash('sha256');for await(const part of createReadStream(actual))hash.update(part);
const record={platform,file:filename,version,signature,channel,bytes:stat.size,sha256:hash.digest('hex'),builtAt:stat.mtime.toISOString()};
const manifestPath=path.join(directory,'releases.json');let records=[];
try{records=JSON.parse(await fs.readFile(manifestPath,'utf8')).releases||[];}catch{/* First real release. */}
const temporary=manifestPath+'.tmp';await fs.writeFile(temporary,JSON.stringify({releases:[...records.filter(value=>value.platform!==platform),record]},null,2)+'\n');await fs.rename(temporary,manifestPath);
console.log(`${platform} ${version}: ${stat.size} bytes verified and registered.`);
