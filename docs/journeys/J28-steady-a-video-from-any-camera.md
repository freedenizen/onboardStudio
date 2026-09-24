# J28 Steady a video from any camera
*Source: #264 (from #140) — stabilising from motion data needs a gyro record that many cameras and
phones do not write.*

1. Select the video; **Stabilisation ▸ Steady ▸ From the picture**. The inspector explains what will
   happen and offers **Measure Motion**.
2. **Measure Motion**: a progress bar follows the measuring (about thirty frames a second of video are
   looked at); **Cancel** stops it. It is done once per video and kept.
3. The preview steadies. **Smoothing** and **Zoom** work as they do for motion data; **Undo** returns
   to the recording.

Tests: `StabilisationUITests.testAVideoIsSteadiedFromItsOwnPicture`. Model: `PictureMotionTests`
(a jittering video is measured, and its frames moved by their corrections stand still).
