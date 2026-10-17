# BYE review database explained

What we built and what happens next | October 16 2026

BYE now has a working database for its own professor reviews. We loaded the PCC professor and course lists, added rules for submitting and reporting reviews, tested those rules, and removed the test data. The website login, review reading, submission and reporting are implemented locally. Jack completed a real email-code submission and we verified its saved answers. Hosted deployment remains pending.

## What this is for

BYE means Before You Enroll. It helps students compare professors before choosing classes. This database gives BYE a place to keep reviews submitted directly by PCC students, so BYE can gradually rely less on Rate My Professors.

Think of the database as a shared notebook with a locked front desk. The notebook holds professors, courses, reviews, and reports. The front desk checks who is submitting a review and whether the answers make sense. Supabase hosts this notebook and handles sign-in identities.

## What we loaded

The database contains 1,425 professor entries and 1,531 course entries from PCC schedule data. These are lists to choose from, not 1,425 reviews. The seed SQL adds the lists and skips existing entries when rerun. It does not copy Rate My Professors reviews.

## How a student will sign in

1. Enter their @go.pasadena.edu email address in BYE.
2. Receive a one-time code in that email inbox and enter it in BYE.
3. Once verified, submit a review or report an existing review.

No school password is shared with BYE. Students do not need to create a BYE password or manage a profile. Supabase keeps a small user record behind the scenes so the database can recognize the same person and prevent duplicates. The website now implements this email-code flow locally. Jack later completed the real school-email code flow and submitted a temporary review. Automated tests use fictional responses and never send real codes.

Email verification proves access to a PCC mailbox. It does not prove that someone is currently enrolled or that they actually took the course they review.


## What a review contains

A review belongs to one professor and one course. It includes a quality rating from 1 to 5, a difficulty rating from 1 to 5, an optional written comment of up to 2,000 characters, and optional answers to seven questions.

| Question | Low answer  -1 | High answer  +1 |
| --- | --- | --- |
| Grading | Lenient | Strict |
| Workload | Light | Heavy |
| Attendance | Optional | Required |
| Clarity | Unclear | Clear |
| Feedback speed | Slow | Fast |
| Tests compared with class | Rarely match class | Closely match class |
| Textbook | Optional | Required |

For every question, 0 means the student chose an answer in the middle. Skipping a question means no answer is saved for it. A skipped answer and a neutral answer are different.

Example: if ten people write reviews but only three answer the grading question, the grading comparison uses those three answers. The other seven are not counted as lenient, strict, or neutral. Neutral answers count as answered, but belong to neither end of the scale.

## How reviews are saved

The app must use the submit_review function: the controlled front desk. It checks the signed-in user has a confirmed PCC email, validates the ratings and question answers, and saves the review and its answers together. A student can submit one review for each professor and course combination.

## How reporting works

A verified PCC user can report a visible review once. Two reports leave it visible. The third report from a different user hides the review automatically. Hidden reviews, their question answers, and their contribution to comparison counts are excluded from public results.

Hiding is not deletion. Administrators can still inspect a hidden review. Three reports are a moderation signal, not proof that a review is false; a future moderation workflow still needs to be built.

## What stays private

Other students cannot read the reviewer ID, the report records, or the school email through the public review queries. Administrators with privileged database access can link reviews to accounts. A student can still reveal their identity in their own comment; automatic filtering of personal information has not been built.


## What we checked

Jack ran the live tests in Supabase with temporary users. Codex also ran 51 checks in an isolated PostgreSQL engine with simulated sign-in records, plus four checks for the helper permission fix. The isolated checks did not test real email delivery or simultaneous reports.

| Live check | Result |
| --- | --- |
| Confirmed PCC test user submits a review | Review and three answers saved |
| Same user repeats the review | Duplicate blocked |
| Unknown question or invalid answer | Submission blocked |
| App user edits a review or reads reviewer ID | Permission denied |
| Read the review and comparison counts | Fields and totals matched |
| Non-PCC user submits or reports | Both blocked |
| Same person reports twice | Duplicate blocked |
| Two different people report | Review stayed visible |
| Third different person reports | Review, answers, and counts hidden |
| Delete the four temporary test users | Their test data removed |

## Why one security warning remains

Supabase warns that signed-in users can call submit_review with elevated permissions. That is intentional: the function needs permission to save a review after checking the student and the inputs. Removing that access would stop review submissions.

We also removed app users' access to a maintenance helper called rls_auto_enable. That helper enables table security automatically. After the fix, its two warnings disappeared. The expected submit_review warning is the only one Jack reported remaining.

## What remains before students can use it

- Sign-in codes now reach any PCC student: Supabase sends them through Brevo (a free email service, 300 a day) from BYE's Gmail address. The {{ .Token }} code templates are unchanged. Review that email confirmation stays enabled. The Brevo key must be renewed by October 2027, or sooner after 90 days without emails.
- The production review page is live at bye-before-you-enroll.pages.dev/reviews/, and the Mac app's "Write a review" button opens it. The experience has no BYE passwords or profile-management screens.
- Connect the Mac app to the database counts. Choose URLSession or supabase-swift before adding a dependency. Jack will write the professor-comparison statistics in Swift.

The database foundation is working. Hosted testing and broader student access are the next stage. No changes to the native Mac app or commits were made in this database session. Secret database credentials must stay out of the app and repository.

## Further reading

[Supabase email code sign in](https://supabase.com/docs/guides/auth/auth-email-passwordless)

[Supabase email delivery requirements](https://supabase.com/docs/guides/auth/auth-smtp)



### Real website test result (Oct 16)

Jack completed the local website sign-in and submission flow and supplied the
receipt ID. Read-only checks found that exact temporary review and all seven
answers; the professor counts matched, including neutral answers. The test label
was present. Cleanup of that one review is prepared but not yet confirmed. Keep
Jack’s real school account. Hosted deployment and confirmation-setting review
remain pending. No code, password, token, or review comment was recorded here.


### Full website integration follow-up

The website now connects live PCC browsing with separate BYE and RMP review
sections, BYE quality/difficulty averages, course filters, paginated reading,
verified form prefilling and owner-only reporting. Existing SQL and permissions
are reused; no migration or live write was made for this integration. AI summaries
and statistical comparisons remain disabled. Real local PCC reads and BYE catalog
reads passed; RMP access and hosted rollout remain pending. The earlier test review
is no longer publicly visible; administrator confirmation of its deletion is
still needed. See the website repo’s docs/LIVE_APP_PREVIEW.md.
