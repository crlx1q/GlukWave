# Local country lookup

Country-only IPv4 and IPv6 ranges from [sapics/ip-location-db user-country](https://github.com/sapics/ip-location-db), published under [Public Domain Dedication and License1.0](https://opendatacommons.org/licenses/pddl/1-0/). This is country-level network data; it contains no listener accounts or tracked visitor history. The runtime does not send visitor IP addresses to a remote geolocation service.

`provenance.json` records retrieval date, original SHA-256 values checked against the publisher's checksum release, compressed SHA-256 values and row counts. CSV rows contain a numeric lower boundary, upper boundary and ISO country code; they were sorted, checked for overlaps and compressed with gzip without changing country assignments.

Update from the project root with `npm run geoip:update`, then restart the server to load the updated ranges. A failed download/checksum validation leaves installed data intact. Geolocation is approximate; private/LAN IPs and unsupported regions fall back to the browser/device language, then English. An explicit language choice always overrides automatic selection in clients.

The origin server uses Express's request IP and the owner's `TRUST_PROXY` setting. It ignores visitor-supplied `CF-IPCountry` headers. Only configure forwarded IP trust for the actual protected reverse-proxy topology.
