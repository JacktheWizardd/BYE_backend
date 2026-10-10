# BYEAPI

Native Swift module for RMP's undocumented GraphQL endpoint. `RMPClient` offers typed professor search and review pages; all production readers share one client/transport. No AI, browser, hosted intermediary, credential store, persistent cookies, third-party webpage resources or automatic redirects.

Transport limits: two concurrent requests, 100 ms start spacing, 15-second request / 25-second resource timeout, three attempts total for transient transport and 429/500/502/503/504 failures. Respect Retry-After up to 30 seconds; longer delays fail visibly rather than retry early. Cancellation interrupts waits. Public IP and requested profiles remain visible to RMP.

Queries and design draw from Amaan's MIT-licensed TypeScript client; see root THIRD_PARTY_NOTICES.md. Native implementation preserves source IDs, text, dates and helpfulRating; it does not adopt current-date fallbacks, missing-connection-as-empty behavior, or automatic first-result selection. Course counts were independently checked against the live endpoint; no unlicensed source code is incorporated.
