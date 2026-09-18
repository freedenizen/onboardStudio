# QA script — M13 motion auto-sync, YouTube upload, sidecar telemetry

| # | Step | Expected |
|---|---|---|
| 1 | Open a project with a video and a data file; set the data input's start position to something wrong | Gauges disagree with the picture |
| 2 | Select the data input, **Auto-Sync by Motion** | A progress bar with Cancel appears; after the analysis the status line reports the channel used, "good match" and the correlation; gauges now agree with the picture |
| 3 | Compare with **Auto-Sync from Timestamps** (GoPro + RaceChrono) | The two start positions agree to within about a second |
| 4 | `swift run overlaygen sync --video clip.MP4 --data log.csv` | Prints the same start position and "(good)" |
| 5 | Add a DJI clip that has its `.SRT` next to it | The video inspector offers **Use Sidecar Data (DJI SRT)**; pressing it adds a data input that follows the video; **Auto-Sync from Timestamps** on another log names the "DJI SRT clock" |
| 6 | Settings ▸ YouTube: paste the OAuth client ID and secret | Fields persist; "Not signed in." |
| 7 | Export, then **Upload to YouTube…** | The upload sheet shows title/description/tags/privacy; **Sign In with Google…** shows a code and opens google.com/device; after approval "Signed in to YouTube." |
| 8 | **Upload** | Progress climbs to 100 %; the watch link appears; **Open** shows the video on YouTube with the chosen privacy |
| 9 | Pull the network cable mid-upload, plug it back | The upload resumes from the confirmed byte and completes |
| 10 | **Sign Out**, then upload again | The sign-in code is asked for again |

## Results (0.11.0, real GoPro + RaceChrono project at Sonoma)

- **Auto-Sync by Motion** from a deliberately wrong start position (1,787,528,000) set the RaceChrono input to 1,787,528,148.41 within about 20 s; the GPS cross-check from M10 puts the true value at 1,787,528,146.8, so the audio match is 1.6 s off, which the sync wizard's ±0.1 s buttons tidy up. The button is disabled while the analysis runs and re-enabled afterwards.
- `overlaygen sync` on the same files: "audio loudness vs speed, correlation 0.94", start position 1,787,528,148.41, in about 15 s (audio only). Picture motion alone, tried during development, was unreliable on this footage (correlation 0.2, off by tens of seconds): the car sits in the pits for the first 4½ minutes with people walking past, which changes as many pixels as driving does. That is why audio is tried first and picture motion is only the fallback for silent clips.
- **Sidecar data** and **Sony XML** are covered by `CompanionTelemetryTests` with synthetic DJI/Sony files; no DJI or Sony clip is in the sample set.
- **YouTube upload** is covered end to end by `YouTubeKitTests` against a scripted mock of Google's endpoints (device code, refresh, resumable upload with a dropped chunk); a live upload needs the user's own Google Cloud OAuth client (`docs/youtube.md`) and was not run here.
