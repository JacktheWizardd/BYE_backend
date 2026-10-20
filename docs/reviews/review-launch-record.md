# Review launch record

How student reviews went live on October 16–17, 2026: what runs where, the decisions behind it, and what to check when something breaks. The website code lives in the separate `BYE_website` repository; this file is the project record.

## What is live

- **Review form:** https://bye-before-you-enroll.pages.dev/reviews/. Any `@go.pasadena.edu` student can sign in with an emailed one-time code and submit a review. Reviews are saved in Supabase through the `submit_review` function.
- **Ways in:**
  - the landing page ("Write a review" under "Search a class", and in the footer)
  - the web demo header
  - the Mac app's "Write a review ↗" button in the professor report, which opens `/reviews/?professor=<name>&course=<SUBJ NNN>`. The form fills in only exact, unambiguous catalog matches.
- **Ratings:** the Mac app keeps using RMP. BYE reviews are collected now and shown later, once there are enough.
- **Web app:** paused. "Use on the web" goes to the fictional sample-data demo (`/demo/`). The live web app (`/app/`), PCC schedules and RMP are disabled in every website environment, so the website makes no PCC or RMP requests.

## Decisions

| Date | Decision |
| --- | --- |
| Oct 16 | Prepared a full switch of the website to live PCC + RMP data, then dropped it: the website would need PCC permitted use and RMP permission, which BYE does not have. |
| Oct 17 | Focus on the Mac app. Keep the website for the demo and the review form. |
| Oct 17 | Open review sign-in to all PCC students (`REVIEW_ACCESS=students`). Reviews no longer carry the test label. |
| Oct 17 | Test only with data saved in the repositories (fixtures). Don't send test traffic to live PCC or RMP. |

## Email delivery for sign-in codes

Supabase sends each code through **Brevo** (free plan), configured as custom SMTP in Supabase **Authentication → Emails → SMTP Settings**.

| Field | Value |
| --- | --- |
| Host / port | `smtp-relay.brevo.com` / `587` |
| Username | Brevo SMTP **Login** (`…@smtp-brevo.com`), from Brevo → Settings → SMTP & API |
| Password | Brevo SMTP key named `Supabase BYE` (stored only in Brevo and Supabase) |
| Sender | `BYE` <`byebeforeyouenroll@gmail.com`>, a verified Brevo sender |

- **Limit:** 300 emails per day, one per code request.
- **Renewal:** the SMTP key expires **October 17, 2027**, and also after **90 days with no emails sent**. If codes stop arriving, generate a new key in Brevo and paste it into Supabase.
- **Spam:** a free Gmail sender can land in spam, and the form tells students to check spam. Fix later with an owned domain (about $10/year), which only needs new SMTP values. No code changes.
- **Why not the alternatives:**
  - Supabase's built-in sender reaches only project-team addresses.
  - Resend's test sender reaches only the Resend account owner.
  - Gmail SMTP with an app password was rejected (`535 Username and Password not accepted`).

## Website hosting fix

Every website push from `e79f6c5` on failed to build. Cloudflare Pages had no build command, so packages were never installed and the review API couldn't load the Supabase library. Production stayed on an older version, which is why `/reviews/` returned 404.

The fix was made in the Pages project settings on Oct 17:
- build command `pnpm install --frozen-lockfile`, output `public`
- `NODE_VERSION=22.23.3` and `PNPM_VERSION=11.25.0`
- production variables `REVIEWS_ENABLED=true`, `REVIEW_ACCESS=students`, `SUPABASE_URL`, and the secret `SUPABASE_PUBLISHABLE_KEY`

Pages ignores the website's `wrangler.pages.jsonc`, so production settings live in the Cloudflare dashboard. The first good deploy was `5591a31b` (commit `29663bb`), followed by `58c5c5f`. `/download` and the update feed were unchanged throughout.

## Troubleshooting

- **"Email verification is unavailable"** means Supabase failed to send the email. In Supabase, open **Logs** with Log Type **Auth** and read the `error` field. Brevo's **Transactional → Logs** shows the same send.
- **"Reviews are not open yet"** means the Pages production variables are missing or invalid.
- **`/reviews/` returns 404** means a Pages build failed. Check the Pages deployment list in Cloudflare.

## Verified

- Jack received a production code through Brevo and reached the review form.
- Automated tests (fixtures only), all passing:
  - 71 unit tests in the website repository, including students mode, rate limits and name-based prefill
  - the browser suites in Chromium and WebKit at phone and desktop widths
  - the Mac app's 189 tests, including the review-link URL builder

## Still to do

- One sign-in by a second PCC student. This is the case the old Resend test sender could not serve.
- Change Supabase's **Site URL** (Authentication → URL Configuration) from `http://localhost:3000` to `https://bye-before-you-enroll.pages.dev`.
- Later: show BYE reviews next to RMP once enough exist, and consider an owned domain for email.
