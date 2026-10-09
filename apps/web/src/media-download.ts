/** Credentials accompany downloads only to this application's own API. */
export function mediaDownloadPath(trackId:string,descriptorUrl:string|undefined,origin:string):string|null{
 if(!descriptorUrl)return `/api/media/${encodeURIComponent(trackId)}/download`;
 try{const url=new URL(descriptorUrl,origin);if(url.origin!==origin||url.username||url.password||!url.pathname.startsWith('/api/'))return null;return url.pathname+url.search;}catch{return null;}
}

export function mediaArtworkPath(trackId:string,artwork:string,origin:string):string{
 try{const url=new URL(artwork,origin);if(url.origin===origin&&!url.username&&!url.password&&url.pathname.startsWith('/api/'))return url.pathname+url.search;}catch{/* The server proxy resolves the track's known source artwork. */}
 return `/api/external-covers/${encodeURIComponent(trackId)}`;
}
