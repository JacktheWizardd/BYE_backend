# Shared update and signing configuration. Sourced after beta-version.sh.
# The EdDSA private key lives only in the release Mac's login Keychain under
# this account; back it up with `generate_keys --account ... -x <file>` to
# offline storage. Never commit an exported key.
UPDATE_KEY_ACCOUNT=bye-before-you-enroll
UPDATE_PUBLIC_ED_KEY=CpVpvUEH+nVuA7BEZ1IJqGfSDPF8DyYL8FAx+DEF78o=
# Updates are served from the public /updates/ folder of the BYE website
# (Cloudflare Pages). Both GitHub repositories stay private.
UPDATE_SITE=${BYE_UPDATE_SITE:-https://bye-before-you-enroll.pages.dev}
# Verification builds may point at a localhost feed with BYE_UPDATE_FEED_URL.
UPDATE_FEED_URL=${BYE_UPDATE_FEED_URL:-$UPDATE_SITE/updates/appcast.xml}
UPDATE_DOWNLOAD_PREFIX=${BYE_UPDATE_DOWNLOAD_PREFIX:-$UPDATE_SITE/updates}
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
# "-" is ad-hoc signing. Set BYE_SIGN_IDENTITY="Developer ID Application: ..."
# and BYE_NOTARY_PROFILE (from `xcrun notarytool store-credentials`) once a
# Developer ID is available.
SIGN_IDENTITY=${BYE_SIGN_IDENTITY:--}
NOTARY_PROFILE=${BYE_NOTARY_PROFILE:-}
