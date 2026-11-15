# J73 — Colour the map by a channel

**Who:** a driver who wants to see on the map where they braked, where they were flat and where
they were slow, lap after lap.
**Issue:** #561. **Driven by:** `MapChannelColourUITests`.

## Steps

1. In a project with a data input, add a **Track Map** (Add Object ▸ Track Map) and select it.
2. In the inspector, **Lap Colour ▸ Colour by** ▸ a channel: *Speed*, a brake pressure, the
   throttle, *Lateral G*, anything the file has.
3. Play the video. The lap being driven is painted from blue (the session's lowest) to red (its
   highest) and repainted as each new lap starts. A legend under the circuit names the channel
   and its range in the object's unit.
4. Untick **Legend** on a small map. Turning on *Colour the lap by time gained and lost* hands the
   line over to the delta colours and sets *Colour by* back to *Nothing*.
5. **Edit ▸ Undo Change Channel Colouring** takes the choice back in one step.
6. To change the colours for every map, use **Settings ▸ Maps**; **Restore Default Colours** puts
   them back.

## What it must get right

- The scale is the session's, so a colour means the same value on every lap. The out-lap and the
  pit lane do not stretch it.
- The circuit is fitted above the legend, never under it.
- A map saved before #561 paints no channel and draws as it did.
- A channel the data input lacks paints nothing and says so in the inspector.
