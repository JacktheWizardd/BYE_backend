# Mac 0.5.0 accessibility checks — October 21, 2026

Scope: the 0.5.0 changes (network back on, BYE score row, one Reviews section with the Both · BYE · RMP toggle, `ByeStamp`, `SourceTag`) in `test/BYE Test.app`, build 10.

## Status

| Check | Real window | Code and test review |
| --- | --- | --- |
| VoiceOver | **Not run** | Done (below) |
| Keyboard only | **Not run** | Done (below) |
| Reduce Motion | **Not run** | Done; `TokenDriftTests.testReduceMotionTurnsAnimationsOff` passes |

The real-window checks were not run because this session could not control the test app:
- Computer use was not turned on.
- `osascript` was refused assistive access (`-1719`).
- Turning on VoiceOver or Reduce Motion, or granting assistive access, are system accessibility setting changes that the agent may not make.

The owner, or an agent with Computer use turned on, still has to run the real-window steps below. Nothing here is real-window evidence.

## Code and test review (done)

**VoiceOver labels**
- `ByeStamp`:
  - an image element labelled "From BYE students · {tier} stamp";
  - the drawing itself is not read separately;
  - a hover tooltip with the same text.
- `SourceTag` "RMP" reads "From Rate My Professors".
- Score tiles read as one element each, for example "BYE quality: 4.2/5" and "BYE reviews: 12". A missing value reads "not available".
- The Reviews toggle is a `Segmented` labelled "Review source". Each option is a button (Both, BYE, RMP), and the chosen one carries the Selected trait.
- "Reviews", "Sections", "BYE student ratings" and "Rate My Professors ratings" are headings.
- Status lines are plain text, so VoiceOver reaches them in reading order. They include "Checking BYE reviews…", "Loading BYE reviews first. RMP reviews follow." and the failure messages with "Try again" / "Retry BYE reviews". They are not announced when they change.

**Keyboard**
- The course filter and sort are standard menu pickers, and Try again / Retry use `TextLinkStyle` buttons. All of them take focus with macOS Keyboard navigation turned on.
- The Both · BYE · RMP options are plain `Button`s, so they too need macOS Keyboard navigation turned on (System Settings → Keyboard), as the existing sort control on the results list does.
- No new shortcut was added. ↑ ↓, ⌘K, ⌘N and ⌘R are unchanged.

**Reduce Motion**
- Every new animation goes through `BYEMotion`, which returns no animation when Reduce Motion is on:
  - card re-ordering (`spring`)
  - the toggle thumb (`glide`)
  - score count-ups (`count`)
  - rating bars (`bars`)
- The stamp's −4° tilt is static and does not move. Body text is never tilted or slid.

## Gaps found

1. Status changes are not announced to VoiceOver. Examples: BYE finishing loading, or "RMP reviews follow". Consider an accessibility announcement when BYE fails or finishes, if real-window testing shows that it matters.
2. **Fixed in this pass:** the score-row labels were not headings, so VoiceOver's heading rotor skipped from the professor's name to "Sections". "BYE student ratings" and "Rate My Professors ratings" now carry the header trait.

## Real-window steps still to run

Use `test/BYE Test.app`. Search a class where a professor has BYE reviews.

1. **VoiceOver** (⌘F5):
   - Open a professor and move through the BYE row, the RMP row, the Reviews toggle, the filter, the sort and the first BYE and RMP cards.
   - Confirm each stamp reads its tier, the RMP tag reads its source and the toggle reads the selected option.
2. **Keyboard only**, with System Settings → Keyboard → Keyboard navigation on:
   - Tab to the toggle and pick each option with Space.
   - Open the filter and sort menus with the keyboard.
   - Reach "View more reviews" and the Try again buttons.
   - Check that the focus ring is visible on each.
3. **Reduce Motion**, with System Settings → Accessibility → Display → Reduce motion on:
   - Switch professors and change the sort and the toggle.
   - Confirm that nothing glides, counts up or springs, and that the stamps stay still.
   - Turn the setting back off afterwards.

Record results under a "Real window" heading in this file, with the macOS version and the date.

## Owner testing, first pass (October 21, 2026)

The owner tried build 10 by hand and reported five issues. All five are fixed in code. Each fix still needs the owner to retest it by hand.

1. **Revisiting a class searched again.** Going Home, opening another class and coming back re-ran the PCC search and re-checked professors.
   - **Fix:** a class revisited this session now reappears from its saved state with no new search.
   - Only professors left unchecked are looked up, and seats follow on the normal schedule poll.
   - Going Home stops the ratings pass before saving, so an unfinished professor resumes on return.
   - **Test:** `ScheduleRefreshTests.testRevisitedClassReappearsWithoutSearchingOrCheckingAgain`.
2. **Professor highlight skipped on fast clicks**, and
3. **highlight flashed black.** Both came from moving the highlight between rows with `matchedGeometryEffect`: fast clicks cross-faded two copies, and the half-faded white card showed its ink shadow.
   - **Fix:** one highlight now always exists and glides to the open row. A new click retargets it from where it is.
4. **No Check for Updates in the test app.**
   - Release builds (`build-app.sh`) always include the feed and the Settings controls.
   - Test builds stay inert unless built with `BYE_TEST_UPDATES=1 ./scripts/build-test-app.sh`, which writes the release feed and key.
   - The live feed's newest entry is 0.4.1 (build 9), so a build-10 test app reports that it is up to date.
5. **No way to remove a class from Your classes.**
   - **Fix:** a × shows when the row is hovered or the × has keyboard focus, as on Windows.
   - The row also has a context menu item and a VoiceOver action, "Remove from Your classes".
   - Removing the open class returns Home.
   - **Test:** `AppPreferencesTests.testForgetRemovesOneClassAndKeepsTheOrder`.

Checks: `swift test` passed 244 out of 244 on four consecutive runs. One earlier run reported 5 failures that did not repeat and printed no failure lines. Test app rebuilt with `BYE_TEST_UPDATES=1`.
