import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {artistKey,toggleArtist,playlistCovers,advancedSettingsChange,recommendationMood} from '../src/parity-model.ts';
const first={id:'42',source:'spotify',name:'Same artist',artwork:''};
const otherSource={...first,source:'youtube'};
const otherIdentity={...first,id:'43'};
test('artist preferences preserve distinct catalogue identities and do not mutate the input',()=>{
 const input=[first];const selected=toggleArtist(input,otherSource);
 assert.equal(input.length,1);assert.equal(selected.length,2);assert.notEqual(artistKey(first),artistKey(otherSource));
 assert.equal(toggleArtist(selected,otherIdentity).length,3);
 assert.deepEqual(toggleArtist(selected,first),[otherSource]);
});
test('playlist collage uses at most four distinct nonempty actual artwork URLs in track order',()=>{
 assert.deepEqual(playlistCovers({coverArtworks:['','one','one','two','three','four','five']}),['one','two','three','four']);
 assert.deepEqual(playlistCovers({}),[]);
});
const current={fontFamily:'manrope',appearance:{radius:24,speed:1,compact:false,blur:true,waveStyle:'silk',cover3d:true,coverKind:'vinyl',light:{bg:'#efede3',surface:'#f8f7f1',ink:'#302f2c',accent:'#a08369'},dark:{bg:'#141517',surface:'#202225',ink:'#eeeae3',accent:'#b1a2de'},amoled:{bg:'#000000',surface:'#0b0b0b',ink:'#f4f1f7',accent:'#b1a2de'}}};
test('free accessibility and basic colors are allowed across every theme',()=>{
 assert.equal(advancedSettingsChange({fontScale:1.25,reducedMotion:true,theme:'amoled'},current),false);
 assert.equal(advancedSettingsChange({appearance:{light:{accent:'#123456'},dark:{accent:'#345678'},amoled:{accent:'#567890'}}},current),false);
 assert.equal(advancedSettingsChange({lyrics:false,comments:false,lyricsUnderCover:false},current),false);
});
test('free accounts retain prior advanced values, but changed advanced settings require a plan',()=>{
 assert.equal(advancedSettingsChange({fontFamily:'manrope',appearance:{radius:24,light:{bg:'#efede3'}}},current),false);
 assert.equal(advancedSettingsChange({fontFamily:'nunito'},current),true);
 assert.equal(advancedSettingsChange({appearance:{radius:26}},current),true);
 assert.equal(advancedSettingsChange({appearance:{amoled:{surface:'#333333'}}},current),true);
});
test('legacy visual mood identifiers map to the server recommendation contract',()=>{
 assert.deepEqual(['personal','calm','focus','energy','night'].map(recommendationMood),['personal','relax','focus','energy','dream']);
});
test('all six catalogs contain every new feature label and preserve interpolation tokens',async()=>{
 const locales=['en','ru','kk','uk','de','es'];const catalogs=await Promise.all(locales.map(async language=>JSON.parse(await fs.readFile(new URL(`../src/locales/${language}.json`,import.meta.url),'utf8'))));
 const keys=Object.keys(catalogs[0]).filter(key=>key.startsWith('parity.'));
 assert(keys.length>100);
 const tokens=text=>[...text.matchAll(/\{(\w+)\}/g)].map(match=>match[1]).sort();
 for(const key of keys)for(const [index,catalog]of catalogs.entries()){
  assert.equal(typeof catalog[key],'string',`${locales[index]} missing ${key}`);assert(catalog[key].trim());
  assert.deepEqual(tokens(catalog[key]),tokens(catalogs[0][key]),`${locales[index]} tokens for ${key}`);
 }
 const files=(await fs.readdir(new URL('../src/',import.meta.url))).filter(file=>file.endsWith('.tsx')||file.endsWith('.ts'));
 for(const file of files){const source=await fs.readFile(new URL(`../src/${file}`,import.meta.url),'utf8');for(const [key]of source.matchAll(/parity\.[a-zA-Z]+/g))if(key!=='parity.css')assert(keys.includes(key),`${file}: ${key} missing`);}
});
