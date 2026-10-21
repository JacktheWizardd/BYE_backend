# Schedule API settings for app builds. Sourced by build-test-app.sh and build-app.sh.
# The BYE application key (bye_pk_…) is created in the owner dashboard and identifies the app, not a student;
# it is meant to ship inside the app. Put it in config/schedule-api.local (ignored by Git), or set
# BYE_SCHEDULE_API_KEY. Never use a Supabase publishable/secret key, a service-role JWT or a job token here.
SCHEDULE_API_URL=${BYE_SCHEDULE_API_URL:-https://nahvhampsxtasfwvvfei.supabase.co/functions/v1/bye-schedule-api}
SCHEDULE_API_KEY=${BYE_SCHEDULE_API_KEY:-}
SCHEDULE_API_FILE=${BYE_SCHEDULE_API_FILE:-config/schedule-api.local}

# Read KEY= (and an optional URL=) from the local file without executing it.
if [ -z "$SCHEDULE_API_KEY" ] && [ -f "$SCHEDULE_API_FILE" ]; then
    SCHEDULE_API_KEY=$(sed -n 's/^[[:space:]]*KEY[[:space:]]*=[[:space:]]*//p' "$SCHEDULE_API_FILE" | tail -n 1 | tr -d '\r"'"'"' ')
    file_url=$(sed -n 's/^[[:space:]]*URL[[:space:]]*=[[:space:]]*//p' "$SCHEDULE_API_FILE" | tail -n 1 | tr -d '\r"'"'"' ')
    if [ -z "${BYE_SCHEDULE_API_URL:-}" ] && [ -n "$file_url" ]; then SCHEDULE_API_URL=$file_url; fi
fi

# Never print the key; messages name only the problem.
schedule_api_fail() { printf 'Schedule API configuration: %s\n' "$1" >&2; exit 1; }
case "$SCHEDULE_API_URL" in
    https://*|http://localhost:*|http://localhost/*|http://127.0.0.1:*|http://127.0.0.1/*) ;;
    *) schedule_api_fail "the URL must be https (or http on localhost)." ;;
esac
case "$SCHEDULE_API_URL" in
    *[!A-Za-z0-9:/._~%-]*|*@*) schedule_api_fail "the URL has characters that are not allowed." ;;
esac
if [ -n "$SCHEDULE_API_KEY" ]; then
    case "$SCHEDULE_API_KEY" in
        bye_pk_paste_the_key_from_the_dashboard) schedule_api_fail "replace the placeholder in $SCHEDULE_API_FILE with the key from the dashboard." ;;
        sb_secret_*|sb_publishable_*) schedule_api_fail "that is a Supabase key. Use the BYE application key (bye_pk_…) from the owner dashboard." ;;
        eyJ*) schedule_api_fail "that looks like a JWT (possibly a service-role key). Use the BYE application key (bye_pk_…)." ;;
        bye_pk_*) ;;
        *) schedule_api_fail "the key must be a BYE application key that starts with bye_pk_." ;;
    esac
    case "$SCHEDULE_API_KEY" in
        *[!A-Za-z0-9_-]*) schedule_api_fail "the key has characters that are not allowed." ;;
    esac
    [ "${#SCHEDULE_API_KEY}" -ge 20 ] || schedule_api_fail "the key is too short."
fi

# Info.plist entries for the app (empty without a key, so the app shows "not configured").
schedule_api_plist() {
    [ -n "$SCHEDULE_API_KEY" ] || return 0
    printf '<key>BYEScheduleAPIURL</key><string>%s</string>\n<key>BYEScheduleAPIKey</key><string>%s</string>\n' "$SCHEDULE_API_URL" "$SCHEDULE_API_KEY"
}
