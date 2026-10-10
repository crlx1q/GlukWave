# Discord presence — 10 October 2026

Gluk Wave uses an OAuth-authorized **server headless-session adapter**. The web and Flutter clients do not publish competing local IPC activities or require a browser extension. On 10 October the owner reported a working hosted integration after fixing OAuth/profile handling, artwork, track transitions and YouTube durations, and configuring the hosting secrets. Those owner changes are preserved. This report confirms the owner's live result; it does not substitute for an independent cross-device verification matrix.

## What was checked before choosing the transport

- [Discord Social SDK presence scopes](https://docs.discord.com/developers/discord-social-sdk/core-concepts/oauth2-scopes) document `openid sdk.social_layer_presence`. The current OAuth request uses exactly those scopes. Profile lookup tries `/users/@me`, then `/oauth2/userinfo` for OpenID identities (`sub`, `preferred_username`, `picture`); `identify` is not added again. Existing `activities.write` grants are also recognized by the presence adapter. We never request a Discord user token or bot login.
- [Discord web account linking](https://docs.discord.com/developers/discord-social-sdk/development-guides/account-linking-on-web) explicitly describes a confidential server exchanging codes and holding the secret. PKCE, one-use state, callback cookie for web, initiating Wave session and a configured callback address are checked.
- [Neurobox](https://github.com/Sheathed/Neurobox) demonstrates OAuth Bearer requests to `/api/v10/users/@me/headless-sessions` and `/headless-sessions/delete`, without a Discord desktop client. Its code was inspected as protocol research; no AGPL source was incorporated into this project. Gluk Wave's adapter is an independent implementation.
- [PreMiD](https://github.com/PreMiD/PreMiD) is an extension-based product; requiring it would not meet the requested installation-free workflow. No PreMiD runtime is bundled.
- An unauthenticated, empty request from Node to the real Discord headless endpoint returned HTTP 401. **This proves reachability, not authorization, scope acceptance or a visible activity.** No real Discord user consent was fabricated or borrowed.

The headless HTTP endpoint is **not a documented, versioned public REST contract** in Discord's published API reference. OAuth scopes and SDK Rich Presence are documented; the bare HTTP transport is not. Permission acceptance for the owner's application, its suitability under Discord's terms and continued endpoint availability require a real application check. Rejection (403/404), token revocation and provider errors are surfaced as unavailable/reconnect/retry states; playback remains independent. `DISCORD_HEADLESS_ENABLED=false` is an operator kill switch. Do not describe this adapter as Discord-certified or guaranteed stable.

## Server behavior

`GET /api/discord` returns only safe identity, settings, status and canonical playback preview. `PATCH /api/discord` changes publishing and join consent. Existing `/api/integrations/discord/connect`, callback and DELETE routes handle link/relink/unlink.

Beta and Unbound checks run on OAuth start/callback, settings changes and every publication. Free cannot enable presence through the generic settings API either. Administrative downgrade, ban, session revocation, account removal and playback disconnect trigger reevaluation. A keepalive also verifies the selected output's actual Wave session, rather than trusting a stored device row or a mirrored controller.

Only the account's selected, authenticated output is published, including room/Jam state. Independent listening still has one selected Discord activity: the currently selected output wins. A paused, ended or disconnected output clears the activity; a 2.5-second idle grace prevents flicker during a track transition. Track changes have a 1.5-second minimum interval, other changes coalesce at 12 seconds, and stable playing sessions refresh at approximately 25 seconds. Relative cover URLs resolve against the public application origin; missing YouTube duration can be hydrated with the existing server metadata key. The worker respects individual and global 429 delays. Headless session and OAuth/refresh tokens are AES-256-GCM encrypted using the existing server encryption key and never returned to clients or logs. Link, refresh, publish and unlink serialize per account so a pending response cannot recreate an unlinked connection. One Discord identity can belong to only one Wave account in this server instance.

Unlink first queues encrypted cleanup, deletes the headless session and revokes the OAuth grant; transient failures remain in a bounded 24-hour cleanup queue. Replacement clears only the old session, avoiding revocation of a newly issued grant for the same Discord application. On restart, stored Connect state does not count as a live device. Shutdown attempts session deletion. Provider outages cannot guarantee immediate remote deletion; queued cleanup is retried. Deploy one presence-publishing Node process: cluster-wide external-I/O locking is not implemented.

## Listening together and track links

Join sharing is **on by default for new connections and records without a saved preference**, as requested by the owner. A saved explicit `allowJoin:false` is preserved on reconnect or relink, including a different Discord identity. A viewer follows `/app/?listen=<host>` and confirms joining. The server verifies that the host is paid, sharing is enabled, the viewer is a Wave friend, an authenticated host output is playing, and all queued tracks are accessible to the viewer. Only then does it reuse/create an ordinary hidden Jam and attach the host's existing output. The shared Jam join function adds the viewer's actual membership before returning: friend checks, five-person capacity and listener controls remain in force. No friendship or room membership is granted by merely displaying a Discord card. Ordinary room listening cannot silently be converted to a Jam.

The second button uses the existing `/app/?track=<id>` route and existing track-access checks. Signed-out viewers retain the pending invite through sign-in. Public Discord links are not an authorization secret.

## Appearance and live verification still required

The payload uses `Listening` type, track details, artist, album cover, start/end timestamps, Gluk Wave's logo asset (or public HTTPS logo) and up to two URL buttons. Covers/logos must be reachable by Discord; localhost/protected files cannot be fetched by Discord. Album art is not uploaded to Discord by this integration.

[Discord's Rich Presence guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/setting-rich-presence) supports external images, timestamps and two buttons. **Discord controls the final rendering.** Spotify's verified integration, connection badge and exact music progress card are not reproducible through an ordinary application payload. Buttons are visible to other viewers, not the activity's owner. Discord privacy/invisible/activity-display settings can hide generic activities. There is no attempt to impersonate Spotify.

Remaining independent live checks (the owner already configured the hosted application and reports it works):

1. Keep the hosted application callback exactly `https://wave.gluk.tech/api/integrations/discord/callback` (or the separately configured local test callback). Normal listeners only click Connect; they never enter API keys. Do not overwrite the owner's working hosting configuration with local QA settings.
2. A consenting Beta/Unbound test user completes real OAuth. Verify `sdk.social_layer_presence` is granted for this application and headless POST returns a session token.
3. Observe the activity from a second Discord account while the listener has **no Discord desktop client running**. Test browser, Windows and Android output transfer, pause, seek, track ending, network loss, revoked Wave/Discord sessions and reconnect.
4. Check both buttons from that second viewer, public HTTPS artwork, owner privacy settings and real provider 429/revocation behavior. Do not claim visual parity solely from the in-app preview or mocked tests.

The historical 1.0.0+7 build checks remain in `docs/verification/2026-10-10/discord-evidence.json`; they predate the owner's subsequent fixes. Current build results are recorded in `outputs/VERIFICATION.md`. Local changes from this continuation have not been deployed by the coding agent; the owner's hosted changes are not rolled back.
