/** Colour only: preserve the folded field and measured audio motion. Deep
 * pigment below, sparse luminous highlights above; never a white ribbon. */
export function silkPalette(tint: string, background: string) {
 const rgb=(hex:string)=>[1,3,5].map(index=>parseInt(hex.slice(index,index+2),16)/255);
 const tone=rgb(tint),bg=rgb(background),dark=bg[0]*.2126+bg[1]*.7152+bg[2]*.0722<.48;
 return {
  base:tone.map(v=>v*(dark?.82:.56)),
  accent:tone.map(v=>dark?v*.68+.30:v*.76+.03)
 };
}

export function silkDepthColor(palette: ReturnType<typeof silkPalette>, depth: number) {
 const amount=Math.max(0,Math.min(1,depth))**3;
 return palette.base.map((value,index)=>value+(palette.accent[index]-value)*amount);
}
