# Third-party components

| Component | License | Used for |
|---|---|---|
| [Sparkle](https://github.com/sparkle-project/Sparkle) 2.x | MIT | In-app updates from GitHub Releases |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 | `onboard` command-line tool |
| [Garmin FIT Swift SDK](https://github.com/garmin/fit-swift-sdk) (from M10) | FIT Protocol License | Importing `.fit` files |
| [ffmpeg](https://ffmpeg.org) (optional, external, not bundled) | LGPL/GPL | Remuxing containers AVFoundation cannot open; test validation |
| [YOLOX](https://github.com/Megvii-BaseDetection/YOLOX)-Nano weights (Megvii), converted to Core ML and bundled | Apache-2.0 (copy in `Sources/MediaKit/Resources/YOLOX-LICENSE.txt`, shipped beside the model) | Finding a car close ahead in onboard video (*Find Traffic in Video*, #573); rebuilt by `Scripts/make-traffic-detector.py` |
| [Gyroflow](https://gyroflow.xyz) (optional, external, not bundled) | GPLv3 | Stabilising a video (*Steady ▸ With Gyroflow*, #263): the user installs it; Onboard Studio runs its command line as a separate program and reads its progress, never linking it |
| [LapViz](https://github.com/lapviz/LapViz.Telemetry) `circuits.json` (data, © Mengal SRL) | MIT — notice shipped as `LICENSE-LapViz.md` in the app's bundled `Tracks` folder | Start/finish and sector lines of the European circuits whose definitions ship with the app (#584); converted by `Scripts/import-lapviz-tracks.py` |
