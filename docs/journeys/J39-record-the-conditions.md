# J39 Record the conditions
*Source: #348 — a 1:56 on a cold morning on new tyres and a 1:56 at 35 °C on worn ones are different
achievements, and six months later nobody remembers which was which. The logger records none of it.*

1. **Window ▸ Logbook**, select the session.
2. Under **Conditions**, pick the **Weather** and the **Track** (dry, damp, wet, drying, greasy),
   type the **Air** temperature in °C, the **Tyres** (compound, age, pressures) and the **Setup**,
   and anything else under **Notes**. Pickers and the temperature are kept as soon as they are set;
   text when you press Return or leave the field.
3. The table's **Conditions** column reads "Sunny · Dry · 24 °C · RE-71RS", with only what you
   filled in, and the search field finds notes and tyres too. Nothing is required.
4. Close and reopen the window, or the app: it is all still there, in the session's own file.

Tests: `LogbookConditionsUITests.testConditionsAreKeptWithTheSession`. Model:
`SessionConditionsTests`.
