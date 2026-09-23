# J17 Keep a layout of your own
*Source: #44 — saving a template was a bare alert, and nothing in the app could rename, remove or
share one afterwards.*

1. Lay out a project, then **Project ▸ Save as Template…**: the sheet shows the layout, and the name
   is one Return away.
2. **Help ▸ Welcome to Onboard Studio**: the template is there beside the built-in ones, with its
   picture.
3. Right-click it: **Rename…**, **Duplicate**; **Delete…** asks before moving it to the Trash.
4. Click it: a new project opens with the layout.

Tests: `TemplateLibraryUITests.testSaveManageAndStartFromYourOwnTemplate`. Model:
`TemplateLibraryTests`, `TemplateThumbnailTests`.
