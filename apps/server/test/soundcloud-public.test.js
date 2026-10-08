import test from 'node:test';
import assert from 'node:assert/strict';
import {parseSoundcloudSearch,parseSoundcloudTrack,readSoundcloudPage,createPublicSoundcloud,soundcloudTrackUrl,publicSoundcloudClient} from '../src/soundcloud-public.js';

const page=(id=293)=>`<script>window.__sc_hydration = ${JSON.stringify([{hydratable:'apiClient',data:{unused:'public-client-fixture'}},{hydratable:'sound',data:{kind:'track',id,urn:`soundcloud:tracks:${id}`,title:'Parser verification',sharing:'public',permalink_url:`https://soundcloud.com/parser/track-${id}`,duration:123456,artwork_url:'https://i1.sndcdn.com/fixture.jpg',user:{username:'Parser QA'}}}])};</script>`;
test('public SoundCloud parser reads track metadata without executing scripts or taking client credentials',()=>{
  assert.equal(soundcloudTrackUrl('https://soundcloud.com.evil.test/a/b'),null);assert.equal(soundcloudTrackUrl('//127.0.0.1/a/b'),null);assert.equal(soundcloudTrackUrl('/parser/sets'),null);
  const tracks=parseSoundcloudSearch('<noscript><h2><a href="/parser/track-293">A &amp; B</a></h2><h2><a href="https://evil.test/ssrf">unsafe</a></h2><h2><a href="/search/sounds">search</a></h2></noscript>');assert.deepEqual(tracks,[{url:'https://soundcloud.com/parser/track-293',title:'A & B'}]);
  const track=parseSoundcloudTrack(page(),tracks[0].url);assert.equal(track.duration,123456);assert.equal(track.user.username,'Parser QA');assert.equal(track.urn,'soundcloud:tracks:293');assert.equal(track.unused,undefined);
  assert.equal(parseSoundcloudTrack(page().replace('"sharing":"public"','"sharing":"private"'),tracks[0].url),null);
});
test('Russian public search preserves UTF-8, hydrates only public tracks and never follows supplied API URLs',async()=>{
  const identifier='a'.repeat(32),calls=[];
  const client=createPublicSoundcloud({fetcher:async(url,options)=>{
    url=new URL(url);calls.push(url);assert.equal(options.headers.Authorization,undefined);assert.equal(options.headers.Cookie,undefined);
    if(url.hostname==='api-v2.soundcloud.com'){
      assert.equal(url.pathname,'/search/tracks');assert.equal(url.searchParams.get('q'),'Кино');assert.equal(url.searchParams.get('client_id'),identifier);assert.equal(options.redirect,'error');
      return Response.json({collection:[{kind:'track',sharing:'public',permalink_url:'https://soundcloud.com/parser/track-293'},{kind:'track',sharing:'private',permalink_url:'https://soundcloud.com/parser/private'},{kind:'track',sharing:'public',permalink_url:'http://127.0.0.1/secret'}],next_href:'http://127.0.0.1/secret'});
    }
    assert.equal(url.hostname,'soundcloud.com');return new Response(url.pathname==='/search/sounds'?`<script>window.__sc_hydration = [{"hydratable":"apiClient","data":{"id":"${identifier}"}}];</script>`:page(),{headers:{'content-type':'text/html'}});
  }});
  assert.equal((await client.search('Кино')).length,1);assert.equal(calls.length,3);
  assert.equal(publicSoundcloudClient('<script>window.__sc_hydration = [{"hydratable":"apiClient","data":{"id":"https://evil.test"}}];</script>'),null);
});
test('public fetch blocks external redirects, limits payloads and reports upstream failures',async()=>{
  let calls=0;
  await assert.rejects(readSoundcloudPage('https://soundcloud.com/parser/track-293',async()=>{calls++;return new Response(null,{status:302,headers:{location:'http://127.0.0.1/private'}});}),error=>error.code==='UNSUPPORTED_URL');assert.equal(calls,1);
  await assert.rejects(readSoundcloudPage('https://soundcloud.com/parser/track-293',async()=>new Response('blocked',{status:429})),error=>error.status===429);
  await assert.rejects(readSoundcloudPage('https://soundcloud.com/parser/track-293',async()=>new Response('x',{headers:{'content-type':'text/html','content-length':String(3*1024*1024)}})),error=>error.code==='SOUNDCLOUD_FORMAT');
});
test('anonymous search reuses metadata and concurrent identical requests while bounding upstream work',async()=>{
  let calls=0,active=0,maxActive=0;
  const client=createPublicSoundcloud({fetcher:async(url,options)=>{
    assert.equal(options.headers.Authorization,undefined);assert.equal(new URL(url).origin,'https://soundcloud.com');calls++;active++;maxActive=Math.max(maxActive,active);
    await new Promise(resolve=>setTimeout(resolve,5));active--;
    const html=new URL(url).pathname==='/search/sounds'?`<noscript><a href="/search/sounds">Tracks</a>${Array.from({length:10},(_,n)=>`<h2><a href="/parser/track-${n+1}">Verification ${n+1}</a></h2>`).join('')}</noscript>`:page(Number(new URL(url).pathname.split('-').at(-1)));
    return new Response(html,{headers:{'content-type':'text/html'}});
  }});
  const [a,b]=await Promise.all([client.search('parser qa'),client.search('parser qa')]);assert.equal(a.length,10);assert.deepEqual(a,b);assert.equal(calls,11);assert.ok(maxActive<=4);
  await client.search('PARSER QA');await client.track(a[0].permalink_url);assert.equal(calls,11);
});
