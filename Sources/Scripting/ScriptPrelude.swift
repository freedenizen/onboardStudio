import Foundation

/// JavaScript evaluated before every user script: helpers and RaceRender-style compatibility
/// names, so scripts written against RaceRender's Enhanced Object API need few changes.
enum ScriptPrelude {
    // swiftlint:disable line_length
    static let source = """
        "use strict";
        // ---- Helpers ----
        function clamp(v, lo, hi) { return Math.min(Math.max(v, lo), hi); }
        function lerp(a, b, t) { return a + (b - a) * t; }
        function formatTime(seconds, decimals) {
            if (seconds === null || seconds === undefined || isNaN(seconds)) return "--:--.--";
            const places = decimals === undefined ? 2 : decimals;
            const total = Math.max(0, seconds);
            const minutes = Math.floor(total / 60);
            const secs = total - minutes * 60;
            const width = places > 0 ? 3 + places : 2;
            return minutes + ":" + secs.toFixed(places).padStart(width, "0");
        }
        function formatDelta(seconds, decimals) {
            if (seconds === null || seconds === undefined || isNaN(seconds)) return "--.--";
            const places = decimals === undefined ? 2 : decimals;
            const text = Math.abs(seconds).toFixed(places);
            if (Number(text) === 0) return text;
            return (seconds < 0 ? "−" : "+") + text;
        }

        // ---- RaceRender-style names ----
        const DFT_Speed = "speed", DFT_RPM = "rpm", DFT_Gear = "gear", DFT_Throttle = "throttle",
              DFT_Brake = "brake", DFT_Latitude = "latitude", DFT_Longitude = "longitude",
              DFT_Altitude = "altitude", DFT_Heading = "heading", DFT_LatG = "lateralG",
              DFT_LongG = "longitudinalG", DFT_Distance = "distance", DFT_Lap = "lap";
        var __rr = { canvas: null, data: null, fill: "#ffffff", stroke: "#ffffff", width: 2, size: 16 };
        function __rrBind(canvas, data) { __rr.canvas = canvas; __rr.data = data; }
        function GetDataValue(channel) { const v = __rr.data ? __rr.data.value(channel) : null; return v === null ? 0 : v; }
        function DataValue(channel) { return GetDataValue(channel); }
        function HasData(channel) { return __rr.data ? __rr.data.has(channel) : false; }
        function GetSpeed(unit) { const v = __rr.data ? __rr.data.speed(unit || "mph") : null; return v === null ? 0 : v; }
        function GetLapNumber() { const l = __rr.data ? __rr.data.lap : {}; return l.number === null || l.number === undefined ? 0 : l.number; }
        function GetLapTime() { const l = __rr.data ? __rr.data.lap : {}; return l.elapsed === null || l.elapsed === undefined ? 0 : l.elapsed; }
        function GetBestLapTime() { const l = __rr.data ? __rr.data.lap : {}; return l.best === null || l.best === undefined ? 0 : l.best; }
        function GetLastLapTime() { const l = __rr.data ? __rr.data.lap : {}; return l.last === null || l.last === undefined ? 0 : l.last; }
        function GetLapDelta() { const l = __rr.data ? __rr.data.lap : {}; return l.delta === null || l.delta === undefined ? 0 : l.delta; }
        function GetTime() { return __rr.canvas ? __rr.canvas.time : 0; }
        function Width() { return __rr.canvas ? __rr.canvas.width : 0; }
        function Height() { return __rr.canvas ? __rr.canvas.height : 0; }
        function __rgba(r, g, b, a) { return "rgba(" + r + "," + g + "," + b + "," + (a === undefined ? 1 : a / 255) + ")"; }
        function SetColor(r, g, b, a) { __rr.fill = __rgba(r, g, b, a); __rr.stroke = __rr.fill; if (__rr.canvas) { __rr.canvas.fill(__rr.fill); __rr.canvas.stroke(__rr.stroke, __rr.width); } }
        function SetLineWidth(w) { __rr.width = w; if (__rr.canvas) __rr.canvas.stroke(__rr.stroke, w); }
        function SetFontSize(s) { __rr.size = s; }
        function DrawRect(x, y, w, h) { if (__rr.canvas) __rr.canvas.rect(x, y, w, h); }
        function DrawRectOutline(x, y, w, h) { if (__rr.canvas) __rr.canvas.strokeRect(x, y, w, h); }
        function DrawRoundRect(x, y, w, h, r) { if (__rr.canvas) __rr.canvas.roundRect(x, y, w, h, r); }
        function DrawLine(x1, y1, x2, y2) { if (__rr.canvas) __rr.canvas.line(x1, y1, x2, y2); }
        function DrawCircle(x, y, r) { if (__rr.canvas) __rr.canvas.circle(x, y, r); }
        function DrawCircleOutline(x, y, r) { if (__rr.canvas) __rr.canvas.strokeCircle(x, y, r); }
        function DrawPolygon(points) { if (__rr.canvas) __rr.canvas.polygon(points); }
        function DrawArc(x, y, r, a1, a2) { if (__rr.canvas) __rr.canvas.arc(x, y, r, a1, a2); }
        function DrawText(x, y, text, size, align) {
            if (!__rr.canvas) return;
            __rr.canvas.text(String(text), x, y, { size: size || __rr.size, align: align || "left", color: __rr.fill, bold: true });
        }
        function DrawNumber(x, y, value, decimals, size, align) { DrawText(x, y, Number(value).toFixed(decimals || 0), size, align); }
        function DrawTime(x, y, seconds, size, align) { DrawText(x, y, formatTime(seconds), size, align); }
        """
    // swiftlint:enable line_length
}
