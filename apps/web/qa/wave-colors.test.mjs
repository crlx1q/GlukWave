import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import { silkPalette, silkDepthColor } from '../src/wave-colors.ts';

const themes={light:'#efede3',dark:'#141517',amoled:'#000000'},accents={copper:'#d98c58',blue:'#579fea'};
const fixture=[];
test('Folded wave preserves chosen pigment in all themes with brighter sparse depth highlights',async()=>{
 for(const [theme,background]of Object.entries(themes))for(const [name,tint]of Object.entries(accents)){
  const palette=silkPalette(tint,background),bands=Array.from({length:8},(_,i)=>silkDepthColor(palette,(i+.5)/8));
  for(const rgb of bands){
   assert(rgb.every(value=>value>=0&&value<=1));
   assert(Math.max(...rgb)-Math.min(...rgb)>.19,JSON.stringify({theme,name,rgb}));
   assert(name==='copper'?rgb[0]>rgb[1]&&rgb[1]>rgb[2]:rgb[2]>rgb[1]&&rgb[1]>rgb[0]);
  }
  assert(bands[7].every((value,index)=>value>bands[0][index]));
  if(theme!=='light')assert(Math.min(...bands[0])<.52,'Deep particles must retain colour, not approach white');
  else assert(Math.max(...bands[7])<.8,'Light-theme pigment stays dark against paper');
  fixture.push({theme,background,tint,bands});
 }
 await fs.writeFile('apps/native/test/fixtures/silk-colors-parity.json',JSON.stringify(fixture,null,2));
});
test('No depth extrapolation or neutral accent hue is invented',()=>{
 const palette=silkPalette('#888888','#000000');
 assert.deepEqual(silkDepthColor(palette,-1),palette.base);
 assert.deepEqual(silkDepthColor(palette,2),palette.accent);
 for(const depth of [0,.25,.75,1]){const rgb=silkDepthColor(palette,depth);assert.equal(rgb[0],rgb[1]);assert.equal(rgb[1],rgb[2]);}
});
