# The new-user review

After every release that adds features (`vX.Y.0`; a patch release is skipped), the published app is
used the way someone who has never seen it would use it: the download from the release page, only
the documentation a user is given, and real track days. Everything that gets in the way is written
down — what the screen failed to say, what the guide failed to say, what was simply wrong — and
becomes issues against the app and against the documentation.

It runs on the release, not on a build of `main`: the point is what a user actually received,
download and disk image included. It is run by Claude with computer use (`/new-user-review 0.37.0`)
and takes the screen while it does.

## What it is, and what it cannot tell you

It is three established methods run together:

- a **cognitive walkthrough** — at each step of a task, ask whether a first-time user would know
  what to do and would see that it worked. This is the method for learnability, which is what a new
  user meets first ([Usability Body of Knowledge][cw]);
- a **heuristic evaluation** against [the checklist](ux-checklist.md) ([NN/g][nn-he]);
- a **test of the documentation**, by doing real tasks with it rather than by reading it.

It is one evaluator, and not a person. That limits what it says, and the report repeats these
limits each time:

- One evaluator finds only part of what is wrong, and a different one would find a different part
  ([Hertzum and Jacobsen][evaluator-effect]). The findings are a floor, not a census.
- Severity from a single rater is unreliable ([NN/g][nn-severity]). The ratings order the work;
  they are not a measurement.
- An agent reads a guide in seconds, does not tire, and feels nothing. Minutes on a task and
  satisfaction mean little from it and are not scored.
- It cannot say how many drivers hit a problem. A finding that turns on that question is marked
  *needs a person*.

It is not the QA of the release either. Whether the app is correct belongs to the tests and to the
[release smoke test](testing.md#release-smoke-test); a wrong number seen on the way is still
filed, as a bug.

## The user

Someone who drives at track days, has what their logger app exports and what their camera
recorded, and is at home on a Mac. They have never seen this app or the one it replaces. They do
not know a file format by name, what a channel is, or anything about how the app is built. What
they want is the round the [User Guide](user-guide.md) is organised by, and every finding belongs
to one stage of it:

| Stage | What they want |
|---|---|
| **Set up** | Car, sessions, data and video in, in whatever order suits them, with mistakes easy to put right |
| **Make videos** | The way to a video with overlays is obvious |
| **Be coached** | Told where the time went and what to try, not handed a table to decode |
| **See progress** | Whether they are getting quicker |
| **Prepare** | Choose where they are going next and get what to practise |
| **Return** | Bring the new day in, see it against the goals, make the new videos |

A finding that serves none of these is a nitpick and ranks last.

## The rules of the walk

1. **Only what a user is given.** The README, the release notes, the User Guide and the pages it
   links to, and whatever the app says itself. Not the source, the tests, `docs/architecture.md`,
   `docs/journeys/`, the rules for building it or anything remembered about how it works. If a step
   can only be justified by knowing the code, a user could not have taken it: that is a finding,
   and the task counts as failed at that point.
2. **Try, then read.** Attempt each task from the screen alone. Open the guide only when stuck —
   two wrong attempts, or nothing on the screen suggests a next step — and record the lookup: what
   was looked for, in which words, where the answer was (or was not), and whether it matched the
   screen. The first place looked is evidence too.
3. **Two questions at every step** (the streamlined walkthrough of Spencer, 2000): *will the user
   know what to do here?* and *having done the right thing, will they know it, and see that they
   are getting somewhere?* A no to either is a finding.
4. **Write it down when it happens**, in the notes file, with a screenshot before and after. A
   finding reconstructed afterwards has lost what was expected at the time, which is half of it.
5. **Observe; do not design.** The note says what was done, what was expected and what happened.
   What to do about it is written after the walk, and kept apart from the observation.
6. **Fix nothing on the way.** A workaround found is used and recorded; the walk goes on.
7. **Record what works.** A step that needed no thought is a result, and is what a later change
   must not break.
8. **Behave as a real install, and no further.** The copy talks to the network as any install
   does: it checks for updates, and it looks up the weather for a session's place and time. Nothing
   else leaves the Mac. Never **Upload to YouTube**, never send what **Export Diagnostics…** saves,
   never share a file.

### The data stays private

The track days are real footage and real GPS traces, and the repository is public. They are for
local use only, as `~/OverlayGenSamples` is.

- No file from the set, and no screenshot showing it, is committed, uploaded or attached to an
  issue. Screenshots stay in the review folder.
- No value read from the data — a lap time, a speed, a position, a session's length — goes into
  the report, an issue, a commit message, a test or a fixture. Say that a number was right or
  wrong, or by how much two readings differ; never the number.
- The review works on clones of the set and never writes to the originals.

## Setting up

The review drives a copy of the release with its own identity, so that it starts as a true first
launch and never touches the real app's Logbook, track library or settings.
[`Scripts/review-copy.sh`](../Scripts/review-copy.sh) makes it:

```sh
# The disk image, as a user gets it: the README's Download link leads to it.
gh release download v0.37.0 --pattern 'OnboardStudio-*.dmg' --dir ~/Downloads

Scripts/review-copy.sh make  0.37.0 ~/Downloads/OnboardStudio-0.37.0.dmg
Scripts/review-copy.sh stage 0.37.0 ~/"Onboard Studio Testing Set"/*/
Scripts/review-copy.sh launch 0.37.0
Scripts/review-copy.sh info  0.37.0     # window frames, in points
Scripts/review-copy.sh clean 0.37.0     # when the review is over; the notes stay
```

- `make` records what Gatekeeper says about the download in `install-check.txt` before it changes
  anything, then gives the copy its own bundle identifier (empty preferences) and re-signs it.
  `launch` gives it its own home folder (an empty Logbook, track library and template folder).
- `stage` puts the track days in the review folder as APFS clones: a day of video is tens of
  gigabytes, a clone of it takes no space and no time, and the originals cannot be altered through
  it. It refuses rather than copy in full.
- Everything is in `~/OnboardStudioReview/v0.37.0` (`ONBOARD_REVIEW_DIR` moves it), outside the
  checkout: notes in `notes.md`, screenshots in `shots/`.
- Sizes in a finding come from `info` or from the accessibility frame, in points — never from the
  pixels of a screenshot, whose scale is not what it seems. A first launch is the size the code
  asks for; a window in a UI-test screenshot is whatever size was last saved.
- The save panel opens on the real Documents folder. Send every save and export into the review
  folder.

### The data

A folder per track day, as it comes off the logger and the camera: the logger's exports and the
camera's chapters together, untouched. The set should hold **two days at the same circuit**. The
earlier is the first visit; the later is the return, which is what puts progress, the plan and the
goals to work. Two different logger formats across the days is better still. Nothing in the
process depends on what the files contain.

## The tasks

Each is a goal in the user's words, with what tells you it is done. None names a button or a menu:
a task that tells the user where to click tests nothing ([NN/g][nn-tasks]). The core set is the
same every release, so one release can be read against the last.

| | Stage | The user's goal | Done when |
|---|---|---|---|
| T0 | Set up | You have heard of the app. Get it onto your Mac and open it. | It is open, and you can say what to do first |
| T1 | Set up | You are home from a track day; the logger's files and the camera's clips are in one folder. Get the day in. | The day shows its sessions with their laps, and each clip is with the session it filmed |
| T2 | Set up | Say which car you drove. Then: one session has the wrong car and the day has the wrong date. Put both right, and take one correction back. | The record is right, and the undo did what its name said |
| T3 | Set up | Find your best lap of the day, and which session it was in. | You can say both, and they agree with the logger |
| T4 | Make videos | Make a video of your best lap, with your speed, a map and the lap time on it, that you could send to a friend. | A file on disk that plays, the gauges moving with the picture |
| T5 | Make videos | Make it yours: move the map, show speed in the other unit, take one gauge away, add brake and throttle. Then change your mind about the last two. | The layout is as wanted, and stepping back was plain |
| T6 | Make videos | Convince yourself the data is in step with the picture. Put it a second out, then put it right. | You can say how you know it is in step |
| T7 | Be coached | Find where you lose the most time against your best lap, and what to try there next time. | You can name the corner and the advice in a driver's words |
| T8 | See progress | Were you getting quicker through the day? | A yes or no you could defend, and where you read it |
| T9 | Prepare | You are going back to the same circuit next month. Find what to work on there, and set yourself a target. | A plan and a goal are recorded, and you know where to find them on the day |
| T10 | Return | Quit. Come back another day and carry on where you were. | The app is as you left it, and nothing had to be found again |
| T11 | Return | It is the next track day at that circuit. Bring it in. | The second day is in; you can say whether you improved on the last visit and against your target |
| T12 | Return | Show your best lap of each day against the other. | Both laps on screen together, level with each other |
| T13 | Any | Things go wrong: add a file the app cannot read, add the same file twice, drop a folder where a file is expected, stop an export halfway. | Each time you were told what happened and what to do, and nothing was lost |
| T14 | Any | Something on the screen means nothing to you. Find out what it is without leaving the app. | You found it, and how |

To these are added **the release's own tasks**: one for each thing the release notes tell a user
is new, written the same way. They test whether a feature that shipped can be found and used by
someone who was only told it exists.

### Three sweeps

Short passes after the tasks, each over the two main windows:

- **Keyboard only.** Reach every control on the way from a day's files to an exported video
  without the pointer (checklist H5).
- **Appearance.** Dark Mode, then Increase Contrast: anything unreadable, anything that was drawn
  rather than left to the system (H7).
- **Labels.** Read the accessibility tree of each window: every control has a label, and the label
  is the word on the screen (H6).

## What is recorded

### For each task

| Measure | What it is |
|---|---|
| **Outcome** | *Unaided* — done from the screen alone. *With the guide* — done after a lookup. *Failed* — not done, or done only with knowledge a user would not have |
| **Lookups** | How many times the guide was opened, and how many of those found the answer |
| **Wrong turns** | Actions that had to be backed out of |
| **Steps, against the shortest way** | Counted after the walk, once the shortest way is known. A large ratio means the path is not the obvious one |
| **First video** | For T4 only: the steps from first launch to a file that plays. The minutes are noted and not scored |

### For each finding

```
R37-07  Set up · T1 · documentation
Did        Dropped the day's folder on the window.
Expected   The sessions to appear in the list.
Happened   A sheet listed the files; the list behind it was unchanged until the sheet was closed.
Evidence   shots/t1-04.png, t1-05.png (window 1000 × 620 pt, from the saved frame)
Breaks     E6, L2 — the guide's step 2 does not mention the sheet
Severity   2
```

- **Kind**: *app* (the screen let the user down), *documentation* (the guide did), or *bug* (it
  did the wrong thing). One event can be two findings: the screen did not say, and neither did the
  guide.
- **A documentation finding says which way the guide failed**: *missing* (not there), *wrong*
  (does not match what shipped — a label that changed, a step left out), *hard to find* (there,
  but not where a user looks — say where they looked), or *assumes* (needs knowledge the user
  lacks). And which kind of page was wanted: a lesson, steps, a fact or a reason.
- **Severity** is Nielsen's scale ([NN/g][nn-severity]), weighing how often it will be met, how
  hard it is to get past, and whether it bites once or every time:

  | | | In this review |
  |---|---|---|
  | 4 | Catastrophe | The task could not be finished even with the guide, or work was lost |
  | 3 | Major | Finished only with the guide, or only by knowing something a user would not |
  | 2 | Minor | A wrong turn or a pause, recovered from the screen alone |
  | 1 | Cosmetic | Noticed; cost nothing |
  | 0 | Not a problem | Withdrawn on re-check. It stays in the log, with the reason |

- **The recommendation** is added after the walk, under its own heading.

## After the walk

In this order. From here on the source may be read.

1. **Check every finding again**, from a fresh launch, before it is written up. The first review
   restated or withdrew four of its fourteen findings at this step: a fixture's artefact, a saved
   window size taken for the first-launch size.
2. **Check what the app showed against an independent reading** of the same files
   (`swift run onboard probe <file>`): the sessions, the lap count, the best lap. A difference is
   a bug finding.
3. **Find the cause** of each finding in the code. The cause goes in the issue; the observation is
   left as it was made.
4. **Check the guide against the screen** for every chapter the walk passed through: each label
   the guide prints in bold is on the screen under that name, each picture shows the app as it
   shipped (checklist L2, L7). This part is mechanical and suits a cheaper model.
5. **Go back over the last review.** Each finding from the previous release's report: *fixed*,
   *still there*, or *back again*. A finding closed in the tracker and still there is the most
   useful line in the report.
6. **Write the report**, `docs/reviews/vX.Y.0.md`.
7. **Show it to the owner; file what they agree to.** One issue per finding, or one for a group of
   small faults on a screen, labelled `bug`, `enhancement` or `documentation` and also
   `new-user-review`. As with every issue here, it states the problem and the evidence, not the
   fix. A documentation finding of the *wrong* kind can be corrected in the PR that carries the
   report.
8. **Clean up**: `Scripts/review-copy.sh clean`.

### The report

`docs/reviews/vX.Y.0.md`, in this shape, so that releases can be laid side by side:

1. **Summary** — three or four sentences: what a new user can and cannot do in this release.
2. **Scorecard** — the task table with outcome, lookups, wrong turns and steps, and the previous
   release's outcome beside each.
3. **Findings** — by stage, most severe first, each in the form above, with its issue number once
   filed.
4. **What worked** — the steps that needed no thought.
5. **Since the last review** — fixed, still there, back again.
6. **The guide** — the lookups: what was looked for and whether it was found; labels and pictures
   that have drifted.
7. **Not covered** — what this run did not reach, and the limits above.

The issue that tracks the review (`New-user review of vX.Y.0`, opened by the
`new-user-review` workflow when the tag is pushed) is closed by the PR that adds the report.

## Why these methods

| What the process does | Where it comes from |
|---|---|
| Two questions at every step | The cognitive walkthrough (Wharton, Rieman, Lewis and Polson, 1994), in Spencer's streamlined form (2000), summarised at the [Usability Body of Knowledge][cw]. It needs a user profile, tasks and the right sequence of actions — here, the user above, the task table, and the guide |
| A checklist with a code for each item | Heuristic evaluation: record which heuristic a problem breaks ([NN/g][nn-he]) |
| Tasks as goals, with no interface words | [NN/g on task scenarios][nn-tasks]: realistic, actionable, and without clues |
| Outcome in three levels, lookups, wrong turns | Effectiveness and efficiency as ISO 9241-11 defines usability; steps against the shortest way is a plain form of the [lostness][lostness] measure |
| No satisfaction score | The usual one, the [Single Ease Question][seq], is a person's own report. An agent's is not evidence |
| Nielsen's 0–4 severity, kept the same every release | [NN/g][nn-severity]; [MeasuringU][mu-severity] on keeping one scale so that results compare, and on recording what worked |
| The guide tested by doing tasks | The four kinds of documentation are [Diátaxis][diataxis] |
| The same core tasks every time | Ours: it is what makes two releases comparable |
| Re-checking before filing, sizes from frames, clones | Ours: each was a mistake made in the reviews of November 2026 |

[cw]: https://www.usabilitybok.org/cognitive-walkthrough/
[nn-he]: https://www.nngroup.com/articles/how-to-conduct-a-heuristic-evaluation/
[nn-severity]: https://www.nngroup.com/articles/how-to-rate-the-severity-of-usability-problems/
[nn-tasks]: https://www.nngroup.com/articles/task-scenarios-usability-testing/
[evaluator-effect]: https://mortenhertzum.dk/publ/IJHCI2003.pdf
[lostness]: https://measuringu.com/lostness/
[seq]: https://measuringu.com/seq10/
[mu-severity]: https://measuringu.com/rating-severity/
[diataxis]: https://diataxis.fr/start-here/
