# BYE student reviews

## What we built and why

BYE has its own voluntarily submitted student ratings and feedback. They remain separate from RMP so provenance, identity, counts and moderation are explicit. School-email verification limits writing access; it does not prove attendance in a particular class.

## How it works

- [Database overview and historical proposal](database.md)
- [Plain-language review database guide](review-database-explained.md)
- [Database decisions and verification history](supabase-plan.md)
- [Review launch record](review-launch-record.md)
- [Canonical submission/API guides in the sibling website repo](../../../BYE_website/docs/reviews/README.md)
- [Windows reading integration](../windows/WINDOWS_API_INTEGRATION.md)

Website owns sign-in, writing, public review endpoints and browser source. Desktop retains its database history and Windows read integration. Never expose privileged credentials, student identities or private review records in documentation.

## What remains

Native Mac review integration and ongoing moderation/retention work require separate implementation and verification. Historical pending items are dated context; consult the website's current guides before assuming a submission feature is still pending or currently deployed.

[All documents](../README.md)
