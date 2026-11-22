# J81 Have a session's weather filled in
*Source: #560 — weather, surface and air temperature had to be typed for every session, and most
drivers never did, so Trends could not explain a slow session and a goal set in the cold could not
be told from one set in the heat, although each session knows where and when it was driven.*

1. Add a session to the Logbook: a track day's files, or a data file added to a project.
2. Select it. Under **Conditions**, **Weather**, **Surface** and **Air** are filled in from the
   weather where and when it was driven, and a line under them says which were looked up, with
   *Weather data by Open-Meteo.com*. Anything already noted is kept.
3. Change one, say Surface from *Dry* to *Damp*: it is yours now, and the line no longer lists it.
4. Sessions that were in the Logbook before are offered once, above the table: **Fill In Weather**
   fills in all of them as one step of **Edit ▸ Undo**; **Not Now** leaves them. **Fill In Weather**
   on a session's right-click menu, or **Session ▸ Fill In Weather**, does it for the sessions
   selected at any time.
5. **Settings ▸ Logbook ▸ Look up the weather for sessions added to the logbook** turns the lookup
   off, and says what is sent: the circuit's position rounded to about 10 km, and the dates.

Tests: `WeatherUITests.testANewSessionsWeatherIsLookedUp`,
`WeatherUITests.testEarlierSessionsAreOfferedOnceAndUndoneAsOne`. Model: `WeatherLookupTests`.
