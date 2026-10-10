export function geniusLyricsUrl(value:string):string|null {
 try{const url=new URL(value.trim());if(url.protocol!=='https:'||!['genius.com','www.genius.com'].includes(url.hostname)||url.username||url.password||url.port||!/^\/[\w%.'-]+-lyrics\/?$/i.test(url.pathname)||/%(?:2f|5c|0[0-9a-f]|1[0-9a-f]|7f)/i.test(url.pathname))return null;url.hash='';url.search='';return url.toString();}catch{return null;}
}

/** One current preview; changing track/account or closing cancels its result. */
export class LyricsRequest {
 private controller:AbortController|null=null;
 cancel(){this.controller?.abort();this.controller=null;}
 start(){this.cancel();const controller=new AbortController();this.controller=controller;return controller;}
 current(controller:AbortController){return this.controller===controller&&!controller.signal.aborted;}
}
