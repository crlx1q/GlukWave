# Iteration 6 — shared contract (9 October 2026)

Root owns server. Native implementer owns apps/native. Web implementer owns apps/web. Do not change production .env, owner data, existing packages or signing identities. Local isolated QA only. Native and web should preserve existing +5 functionality and make new server-backed features accessible with friendly loading/error/empty states, never mock success.

## Shared new API contract

Artist = `{id,name,source,artwork,sourceUrl?,trackIds?:string[]}`. Only catalogue/search results are accepted as artist selections; no fixture artists in product.

- `GET /api/artists?q=&source=all|youtube|soundcloud|spotify|local` -> `{artists:Artist[],genres:string[]}`. Empty q returns actual known catalogue; nonempty q uses catalogue/provider search.
- `GET /api/artists/:id` -> `{artist:Artist,tracks:Track[]}`. Known catalogue artists; clients can use normal search by real artist name when provider only returned metadata without tracks.
- `GET /api/taste` -> `{taste:{artists:Artist[],onboardingCompleted:boolean,onboardingStep:number,automatic:boolean,revision:number},learnedArtists:Artist[]}`.
- `PUT /api/taste` -> same envelope. Partial body `{artists?:Artist[],onboardingCompleted?:boolean,onboardingStep?:0|1|2|3,automatic?:boolean}`. `DELETE /api/taste/learned` clears inferred preferences only.
- `GET /api/recommendations?mood=personal|relax|focus|energy|dream` -> `{tracks:Track[],artists:Artist[],genres:string[],reason:'taste'|'history'|'catalogue'|'empty'}`. Real scored library/catalogue, never claim a model exists. Taste persists across clients; resumable optional onboarding and settings editor. Explicit skip completes onboarding with zero artists. Existing accounts get optional prompt/settings entry; do not hijack playback on each login.

- `GET /api/friends` -> `{friends:[{user:PublicProfile,online:boolean,activity?:{track:Track|null,position:number,playing:boolean,device:{name,kind}|null,jamId:string|null}}],incoming:[{id,from:PublicProfile}],outgoing:[{id,to:PublicProfile}]}`.
- `GET /api/users/search?q=` -> `{users:[PublicProfile & {relationship:'none'|'pending'|'friend'}]}`; auth required, min 2 characters.
- `POST /api/friends/requests {userId}` -> `{request}`; `PUT /api/friends/requests/:id {accept:boolean}` -> `{ok:true}`; `DELETE /api/friends/:userId` -> `{ok:true}`. Notifications via `friends:changed` on own socket; use refresh if unavailable.
- `GET/PATCH /api/account/privacy` -> `{privacy:{showActivity,profileStats,allowFriendRequests}}`; only those optional booleans accepted.
- `POST /api/jams {}` -> `{room:Room}` (host). `POST /api/jams/:id/join {}` -> `{room:Room}`. Friends of host only; at most 5; hidden/temporary; same existing room socket and transport. Reuse room leave/delete routes; host leaving closes jam; local listener pause can mute locally without pausing host. `GET /api/jams/:id` -> `{room:Room}` for members. Each Room includes optional `type:'room'|'jam'`. Host controlled queue; normal own device switching/permissions remain. Never show jams in public rooms. Friend activity exposes joinable host `jamId`; user starts jam explicitly, no covert autoplay.

- `GET /api/account/stats` -> `{stats:{plays,listeningSeconds,trackCount,artistCount,topTracks:[{track:Track,plays,seconds}],topArtists:[{name,plays,seconds}]}}`. Listening seconds use accepted actual output heartbeats; starts count as plays; seek does not create duration. No fabricated counters.
- `GET /api/profile/:id` retains `{user,playlists}` and adds `stats:Stats|null` per privacy. Role/plan badge to right of display name, Beta not a buyable card.

- Existing POST/PATCH playlists also accept `public?:boolean`; GET `/api/playlists/:id` -> `{playlist,tracks}` owner or public. Public lists cannot expose private tracks; invalid publication rejected. `GET /api/playlists/discover?q=` -> `{playlists}` auth optional. `POST /api/playlists/:id/cover` multipart file -> `{playlist}` and DELETE same path restores collage. Uploaded cover cleanup is server-side; use 1–4 track cover collage when artwork empty. `coverArtworks:string[]` provided with each playlist.
- Existing settings PATCH adds `comments?:boolean`, `lyricsUnderCover?:boolean`, `fontFamily?:'manrope'|'nunito'|'system'`, `fontScale?:0.85..1.25`; detailed appearance changes require Beta/Unbound, while theme/basic accent/reduced motion/font size are free. Keep accessibility available to free. Existing free accounts can retain prior settings; reject new advanced changes with PLAN_LIMIT and clear UI.
- Import endpoints require Beta/Unbound (403 PLAN_LIMIT), including manual file and provider import. Provider availability independent of plan.

- Existing `POST /api/account/password {currentPassword,password}` retained. `POST /api/account/email {email,currentPassword}` -> `{ok:true,confirmationRequired:true}` sends one-use confirmation to new email; no fake mail success when SMTP absent outside test. `POST /api/account/email/confirm {token}` -> `{ok:true,user}`. `DELETE /api/account {currentPassword,confirmation:username}` -> `{ok:true}`, purges own media/assets, sessions and relationships. Native/web clear local private state only after success.
- Existing admin PATCH users handles role/plan/blocked; ban revokes sessions. `DELETE /api/admin/users/:id {confirmation:username}` actual account removal, cannot self-delete via admin endpoint. `GET/PATCH /api/admin/registration` -> `{registration:{enabled:boolean}}`. Existing `/api/config` adds `registration:{enabled}`.
- Admin release upload: `POST /api/admin/releases/:platform` multipart file plus version, channel, signature; owner rights only, validate file magic/name/size/hash. GET existing `/api/releases`; preserve fallback local outputs; no fake package entries. UI must not present unsigned APK as store release or unsigned installer as Authenticode signed.

Error responses preserve `{error:{code,message}}`; all clients translate friendly new codes. No developer/API-key prompts outside admin. Endpoints may initially 404 while root implements: don't bake fake data into UI. Inform root of actual required schema changes before work diverges.
