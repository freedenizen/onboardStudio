# What "user-friendly" means here: the checklist

"User-friendly" is not a matter of taste in this project. It is the list below: questions that can
be answered yes or no by looking at a screen, each taken from a source that says why. The
[new-user review](new-user-review.md) holds every release against it, and a finding names the item
it breaks (`C4`, `N9`). It is also the list to read before designing a screen;
`.claude/rules/appui.md` says how this app builds what the list asks for.

Where a source is named, the rule was read on that page in November 2026. Items marked *(ours)* have
no source we could confirm: they are this project's own rules, learnt from its earlier reviews, and
say so rather than borrow an authority.

## The ten heuristics

Jakob Nielsen's [ten usability heuristics][nn-ten] are the general test, and the lettered sections
that follow are these ten made specific to a Mac app that takes in files and makes videos.

| | Heuristic | Asked of a screen |
|---|---|---|
| N1 | Visibility of system status | Does it say what is happening, soon enough to matter? |
| N2 | Match between the system and the real world | Are the words the driver's, not the program's? |
| N3 | User control and freedom | Is there a marked way out, and an undo? |
| N4 | Consistency and standards | Does the same word or action mean the same thing everywhere, and what it means on a Mac? |
| N5 | Error prevention | Was the mistake made impossible, or caught before it cost anything? |
| N6 | Recognition rather than recall | Is what can be done visible, or must it be remembered? |
| N7 | Flexibility and efficiency of use | Is there a faster way for someone who knows the app? |
| N8 | Aesthetic and minimalist design | Is anything on the screen irrelevant or rarely needed? |
| N9 | Help users recognize, diagnose, and recover from errors | Does the message say, in plain words, what went wrong and what to do? |
| N10 | Help and documentation | Can the help be searched, does it follow the task, and does it give steps? |

A heuristic that is broken is not always a problem: the [same source][nn-he] says a violation has
to be weighed in its context. That weighing is the severity rating in the review.

## A. First launch

- **A1** Does the first screen get the user to something real quickly, without a setup they must
  finish first? Nonessential setup is postponed and there are "reasonable default settings so most
  people can immediately start". [HIG: Onboarding][hig-onboarding]
- **A2** Is any teaching done by doing — the user tries the action — or by a tip beside the thing
  it describes, rather than by pages to read? [HIG: Onboarding][hig-onboarding]. NN/g goes further:
  avoid onboarding wherever the screen can explain itself. [NN/g: onboarding][nn-onboarding]
- **A3** Can a tour be skipped, does it stay away once seen, and can it be found again?
  [HIG: Onboarding][hig-onboarding]
- **A4** Is a permission asked for when the feature that needs it is first used, not at launch?
  [HIG: Onboarding][hig-onboarding]
- **A5** Is the user asked only for what the app cannot find out itself?
  [HIG: Settings][hig-settings], [HIG: Entering data][hig-entering]
- **A6** Is there something to try before the user's own files are in — a sample that opens in one
  step? *(ours; NN/g mentions demo data as one way into an empty screen, [NN/g: empty
  states][nn-empty])*
- **A7** Does the download open without a warning from macOS, and does the disk image say what to
  do with it? *(ours)*

## B. Empty panes

All from [NN/g: empty states][nn-empty]; Apple's guidance has no page on them that we could read.

- **B1** Does an empty pane say which it is — still loading, nothing here yet, nothing matches, or
  something failed? "Totally empty states cause confusion about how and whether the system is
  working."
- **B2** Does it say what the pane is for and how something gets into it?
- **B3** Does it carry the button that starts that, not only a description of it?
- **B4** Is "nothing here" never shown while the content is still being read?

## C. Bringing files in

- **C1** Does drag and drop work wherever a file could sensibly go, and is there a menu item or
  button that does the same? [HIG: Drag and drop][hig-dnd]
- **C2** Can several files, or a folder, be dropped at once, and can the drop be undone? "Prefer
  letting people undo a drag-and-drop operation." [HIG: Drag and drop][hig-dnd]
- **C3** Does a file the app cannot use say so, and why? "Show people when a command can't be
  carried out and help them understand why." [HIG: Feedback][hig-feedback]
- **C4** Does the open panel's button name the task (Add, Import), not just Open?
  [HIG: File management][hig-files]
- **C5** After a batch, is there one account of what happened to every file — taken, skipped and
  why, already there? *(ours)*
- **C6** Is a file that is already in recognised, rather than added twice? *(ours)*
- **C7** Is it plain afterwards where each thing went, without hunting? *(ours)*
- **C8** While a file is dragged over the window, does the place that will take it show itself, and
  only while the file is over it? "Show people whether a destination can accept dragged content."
  [HIG: Drag and drop][hig-dnd]

## D. Showing a lot without showing everything

- **D1** Are the essentials shown first, with the control that reveals the rest visible and
  labelled, and no more than two levels deep? [NN/g: progressive disclosure][nn-disclosure]
- **D2** Is the split between first and second level made by how often a thing is used, and is
  there one way to the second level, not several? [NN/g: progressive disclosure][nn-disclosure]
- **D3** Is the sidebar at most two levels, grouped, able to be hidden but not hidden to begin
  with, and free of anything critical at its foot? [HIG: Sidebars][hig-sidebars]
- **D4** Is every toolbar item also a command in the menu bar? [HIG: Toolbars][hig-toolbars]
- **D5** Can an option that belongs to a task be reached from the task, without opening Settings?
  [HIG: Settings][hig-settings]
- **D6** Does a new object, project or day arrive with defaults good enough to use untouched?
  *(ours)*

## E. Saying what is going on

- **E1** Does anything over a second show that it is working, and anything over ten seconds a
  percent-done indicator with a way to stop it? The limits are 0.1 s (feels instant), 1 s (thought
  is not interrupted) and 10 s (attention is lost). [NN/g: response times][nn-times]
- **E2** Is progress determinate whenever the amount of work is known, and does the bar keep moving
  and tell the truth? [HIG: Progress indicators][hig-progress]
- **E3** Does the wording say what is being done, not just "Loading"?
  [HIG: Progress indicators][hig-progress]
- **E4** Can a long job be cancelled, with a warning only where stopping loses something?
  [HIG: Progress indicators][hig-progress]
- **E5** Can the user keep working while something loads or renders? [HIG: Loading][hig-loading]
- **E6** Is status shown quietly, near what it is about, and a finished job announced only when it
  is one worth announcing? [HIG: Feedback][hig-feedback]
- **E7** When a long job ends, is the result one step away — the file shown, the next action
  offered? *(ours)*

## F. Mistakes

- **F1** Is the message beside the problem, free of blame, and clear about the remedy?
  [HIG: Writing][hig-writing]
- **F2** Is it in plain words, exact about what went wrong, with no code unless the code helps a
  diagnosis, and is what the user had entered still there? [NN/g: error messages][nn-errors]
- **F3** Is an alert's title something other than "Error"? [HIG: Alerts][hig-alerts]
- **F4** Are alerts rare? "Avoid displaying alerts for common, undoable actions, even when they're
  destructive." [HIG: Alerts][hig-alerts]
- **F5** Is undo the safeguard, with a confirmation kept for what cannot be undone and comes as a
  surprise? [HIG: Feedback][hig-feedback], [NN/g: confirmation dialogs][nn-confirm]
- **F6** Does a confirmation name the thing and what will happen to it, with buttons that are
  verbs (Delete, Replace) and a Cancel that Esc presses — never "Are you sure?" with Yes and No?
  [HIG: Alerts][hig-alerts], [NN/g: confirmation dialogs][nn-confirm]

## G. Words

- **G1** Is the language plain, and the driver's own — session, lap, corner — rather than the
  program's — input, channel index, asset? [HIG: Writing][hig-writing], N2
- **G2** Is each thing called by one name everywhere: on the screen, in the menus, in the guide and
  in the release notes? "Create a list of common terms, and reference that list."
  [HIG: Writing][hig-writing]
- **G3** Are menu items and buttons in title-style capitals, and help tags in sentence case?
  [HIG: Menus][hig-menus], [HIG: Offering help][hig-help]
- **G4** Does an item end in an ellipsis exactly when it needs more from the user before it can
  act? [HIG: Menus][hig-menus]
- **G5** Are buttons verbs? [HIG: Writing][hig-writing]
- **G6** Does a number carry its unit, and the unit the user chose? *(ours)*

## H. Being a Mac app

- **H1** Are the standard menus there, in order — app, File, Edit, View, the app's own, Window,
  Help — with commands that do not apply dimmed, not removed? [HIG: The menu bar][hig-menubar]
- **H2** Does Edit name what Undo will undo, and can several steps be undone?
  [HIG: The menu bar][hig-menubar], [HIG: Undo and redo][hig-undo]
- **H3** Is Settings in the app menu at ⌘, and does it reopen on the pane last used?
  [HIG: Settings][hig-settings]
- **H4** Is everything in a context menu also in the main interface?
  [HIG: Context menus][hig-context]
- **H5** Can the main path be driven from the keyboard alone, with no system shortcut taken over?
  [HIG: Accessibility][hig-accessibility]
- **H6** Does every control have a VoiceOver label? [HIG: Accessibility][hig-accessibility]
- **H7** Does it hold up in Dark Mode and with Increase Contrast, with text at 4.5:1 or better?
  [HIG: Accessibility][hig-accessibility]
- **H8** Does a window open at a size that shows its controls whole, and come back where it was
  left? [HIG: Launching][hig-launching]; *the first-launch size is ours — it is the one size every
  new user sees*

## I. Coming back

- **I1** Does the app reopen as it was left: the same windows, the same place?
  [HIG: Launching][hig-launching]
- **I2** Are recent things offered, so nothing has to be found twice?
  [HIG: File management][hig-files]
- **I3** Is anything the user must remember from last time shown instead — which day was imported,
  what was planned, what the goal was? N6
- **I4** Is a feature that is new since the last visit pointed out where and when it becomes
  useful, not only in a list at launch? [NN/g: onboarding][nn-onboarding]
- **I5** Does bringing in the next day take fewer steps than the first, and say what changed since
  the last one? *(ours)*

## J. Charts and numbers

- **J1** Is the range of each axis chosen on purpose, with tick values a person would pick?
  [HIG: Charts][hig-charts]
- **J2** Does the chart say what it shows, in a title or a line of summary?
  [HIG: Charts][hig-charts]
- **J3** Is colour never the only thing telling two series apart?
  [HIG: Charts][hig-charts], [HIG: Accessibility][hig-accessibility]
- **J4** Can what matters be read without hovering or clicking? [HIG: Charts][hig-charts]
- **J5** Do axes and legends carry units, and is a legend there whenever there are two series?
  *(ours)*

## K. Help

- **K1** Is the screen understood without the guide? When the guide is needed, is it reachable
  from where the question arose? N10
- **K2** Does the Help menu start with the app's help and hold only a few other items?
  [HIG: The menu bar][hig-menubar]
- **K3** Does a help tag say what the control does in a line, without repeating its name?
  [HIG: Offering help][hig-help]
- **K4** When the app sends the user to a setting, is it a button that goes there, not a
  description of where it is? [HIG: Writing][hig-writing]

## L. The guide itself

The documentation is part of the product, and is reviewed with it. These are our own rules; the
four kinds of page come from [Diátaxis][diataxis], and the first two rules follow John Carroll's
minimal manual, which we know only at second hand.

- **L1** Does the guide start from what the user wants to get done, in the order they do it?
- **L2** Does each step name what is on the screen, by the label the screen uses now?
- **L3** Is nothing assumed that a driver new to the app would not know — a format's name, what a
  channel is, where a file is kept?
- **L4** Is each need served by the right kind of page: a lesson to learn by (tutorial), steps to a
  goal (how-to), facts to look up (reference), the reasons (explanation)?
- **L5** Can the answer be found from the words the user would search for, not only the feature's
  name?
- **L6** Does the guide say what to do when the step goes wrong?
- **L7** Does every picture show the app as it ships?

## What this list cannot do

It is a list for one reviewer, and a single reviewer finds only part of what is wrong: different
evaluators using the same method on the same interface find markedly different problems
([Hertzum and Jacobsen][evaluator-effect]). Nielsen's own advice is three to five evaluators
([NN/g: heuristic evaluation][nn-he]). The list says what to look at; it does not say how often
real drivers trip over a thing, or how they feel about it. Only watching one of them does.

[nn-ten]: https://www.nngroup.com/articles/ten-usability-heuristics/
[nn-he]: https://www.nngroup.com/articles/how-to-conduct-a-heuristic-evaluation/
[nn-onboarding]: https://www.nngroup.com/articles/mobile-app-onboarding/
[nn-empty]: https://www.nngroup.com/articles/empty-state-interface-design/
[nn-disclosure]: https://www.nngroup.com/articles/progressive-disclosure/
[nn-times]: https://www.nngroup.com/articles/response-times-3-important-limits/
[nn-errors]: https://www.nngroup.com/articles/error-message-guidelines/
[nn-confirm]: https://www.nngroup.com/articles/confirmation-dialog/
[hig-onboarding]: https://developer.apple.com/design/human-interface-guidelines/onboarding
[hig-launching]: https://developer.apple.com/design/human-interface-guidelines/launching
[hig-settings]: https://developer.apple.com/design/human-interface-guidelines/settings
[hig-entering]: https://developer.apple.com/design/human-interface-guidelines/entering-data
[hig-dnd]: https://developer.apple.com/design/human-interface-guidelines/drag-and-drop
[hig-feedback]: https://developer.apple.com/design/human-interface-guidelines/feedback
[hig-files]: https://developer.apple.com/design/human-interface-guidelines/file-management
[hig-sidebars]: https://developer.apple.com/design/human-interface-guidelines/sidebars
[hig-toolbars]: https://developer.apple.com/design/human-interface-guidelines/toolbars
[hig-progress]: https://developer.apple.com/design/human-interface-guidelines/progress-indicators
[hig-loading]: https://developer.apple.com/design/human-interface-guidelines/loading
[hig-writing]: https://developer.apple.com/design/human-interface-guidelines/writing
[hig-alerts]: https://developer.apple.com/design/human-interface-guidelines/alerts
[hig-menus]: https://developer.apple.com/design/human-interface-guidelines/menus
[hig-menubar]: https://developer.apple.com/design/human-interface-guidelines/the-menu-bar
[hig-undo]: https://developer.apple.com/design/human-interface-guidelines/undo-and-redo
[hig-context]: https://developer.apple.com/design/human-interface-guidelines/context-menus
[hig-accessibility]: https://developer.apple.com/design/human-interface-guidelines/accessibility
[hig-charts]: https://developer.apple.com/design/human-interface-guidelines/charts
[hig-help]: https://developer.apple.com/design/human-interface-guidelines/offering-help
[diataxis]: https://diataxis.fr/start-here/
[evaluator-effect]: https://mortenhertzum.dk/publ/IJHCI2003.pdf
