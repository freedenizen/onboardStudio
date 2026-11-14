# J66 Keep an autocross on its course
*Source: #552 — an autocross car park is a new layout every event and a hill climb the same road
every visit, but the Logbook kept personal bests per circuit, so runs on unrelated layouts were
compared with each other, and a session's runs read again as laps.*

1. Add a session recorded in runs to the Logbook — a VBO file with a start and a finish gate, or
   a file set to Runs in a project.
2. Select it. The detail lists **Runs**, the unfinished one marked **DNF**, its best and optimal
   run and no fastest rolling lap, and the **Course** it was driven on, *Course of 13 Nov 2026*.
3. Type a name in **Course** and press Return: the course is renamed for every session on it, and
   the sidebar lists it under its new name. **Edit ▸ Undo Rename Course** takes the name back.
4. The button beside it puts the session on another course (**Same Course as ▸**) or on a new one
   (**New Course**), each one step of Undo.

Tests: `CoursesUITests.testRunsAreKeptOnACourseThatCanBeRenamed`. Model: `RunCourseTests`,
`RunImportTests.aFileWithGatesGoesIntoTheLogbookInRunsOnACourse`.
