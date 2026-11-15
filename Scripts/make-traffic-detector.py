#!/usr/bin/env python3
"""Rebuilds Sources/MediaKit/Resources/TrafficDetector.mlmodelc, the traffic detector (#573).

The model is YOLOX-Nano (Megvii, Apache-2.0, trained on COCO), converted to a Core ML ML Program in
FP16 at a 640 x 640 input, with the network's raw head as its output: decoding and non-maximum
suppression are in Swift (`VideoTraffic.detections`). Not run by any build: the compiled model is
committed, and this records how it was made, so a newer model can replace it the same way.

Needs Python 3.10+ with torch and coremltools, the YOLOX source and the Nano checkpoint:

    git clone --depth 1 https://github.com/Megvii-BaseDetection/YOLOX.git /tmp/yolox
    curl -LO https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_nano.pth
    python3 Scripts/make-traffic-detector.py /tmp/yolox yolox_nano.pth

Never use Ultralytics' YOLO or anything loaded through its package: it is AGPL-3.0, and this
repository is MIT. See docs/traffic.md.
"""

import pathlib
import shutil
import subprocess
import sys
import tempfile
import types

def _stub(attribute: str):
    """Anything a stubbed module is asked for is a function doing nothing; dunders stay absent."""
    if attribute.startswith("__"):
        raise AttributeError(attribute)
    return lambda *args, **kwargs: None


# YOLOX imports these at import time for training and evaluation; the model needs none of them.
for name in ["torchvision", "cv2", "tabulate", "psutil", "thop", "pycocotools", "pycocotools.coco",
             "pycocotools.cocoeval", "tensorboard", "onnx", "onnxsim"]:
    module = types.ModuleType(name)
    module.__getattr__ = _stub
    sys.modules[name] = module


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    source, checkpoint = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    sys.path.insert(0, str(source))
    import coremltools as ct
    import torch
    from yolox.exp import get_exp

    exp = get_exp(str(source / "exps/default/yolox_nano.py"), None)
    model = exp.get_model()
    model.load_state_dict(torch.load(checkpoint, map_location="cpu", weights_only=True)["model"])
    model.eval()
    model.head.decode_in_inference = False
    example = torch.zeros(1, 3, 640, 640)
    with torch.no_grad():
        traced = torch.jit.trace(model, example)
    converted = ct.convert(
        traced, inputs=[ct.TensorType(name="images", shape=(1, 3, 640, 640))], convert_to="mlprogram",
        compute_precision=ct.precision.FLOAT16, minimum_deployment_target=ct.target.macOS14)
    out = pathlib.Path(__file__).resolve().parent.parent / "Sources/MediaKit/Resources/TrafficDetector.mlmodelc"
    with tempfile.TemporaryDirectory() as folder:
        package = pathlib.Path(folder) / "TrafficDetector.mlpackage"
        converted.save(str(package))
        subprocess.run(["xcrun", "coremlcompiler", "compile", str(package), folder], check=True)
        shutil.rmtree(out, ignore_errors=True)
        shutil.copytree(pathlib.Path(folder) / "TrafficDetector.mlmodelc", out)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
