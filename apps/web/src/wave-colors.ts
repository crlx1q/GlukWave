/** Colour only: preserve the folded field and measured audio motion. Deep
 * pigment below, sparse luminous highlights above; never a white ribbon. */
export function silkPalette(tint: string, background: string) {
 const rgb=(hex:string)=>[1,3,5].map(index=>parseInt(hex.slice(index,index+2),16)/255);
 const source=rgb(tint),mid=(Math.max(...source)+Math.min(...source))/2;
 const tone=source.map(value=>Math.max(0,Math.min(1,mid+(value-mid)*1.4))),bg=rgb(background),dark=bg[0]*.2126+bg[1]*.7152+bg[2]*.0722<.48;
 return {
  base:tone.map(v=>v*(dark?.88:.50)),
  accent:tone.map(v=>dark?v*.82+.17:v*.72+.02)
 };
}

/** A target may change while the previous cover colour is still settling. */
export function easeWaveColor(current:number[],target:number[],seconds:number) {
 const amount=1-Math.exp(-Math.max(0,seconds)*2.6);
 return current.map((value,index)=>value+(target[index]-value)*amount);
}

export function waveColorHex(color:number[]) {
 return '#'+color.map(value=>Math.round(Math.max(0,Math.min(1,value))*255).toString(16).padStart(2,'0')).join('');
}

export function silkDepthColor(palette: ReturnType<typeof silkPalette>, depth: number) {
 const amount=Math.max(0,Math.min(1,depth))**3;
 return palette.base.map((value,index)=>value+(palette.accent[index]-value)*amount);
}
