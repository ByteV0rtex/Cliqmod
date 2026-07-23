# Cliqmod Brain ↔ Mac Companion Serial Protocol (v1)

Carried over the same native USB port already used for HID keyboard output — the brain's
`USB CDC On Boot` setting means that port is already a composite HID + serial device, so
no new cable or connection is needed.

## Framing

Every protocol message is exactly one line: a fixed prefix, a compact JSON object, and a
newline.

```
CLIQ1|{"type":"...", ...}\n
```

The brain's existing human-readable debug logs (`[WIFI] ...`, `[MACRO] Fired: ...`, etc.)
are unaffected and keep printing on the same stream — they just don't start with
`CLIQ1|`, so the Mac app's line reader filters on that prefix and ignores everything else
as plain debug text.

Baud rate: 115200 (already set via `Serial.begin(115200)` in the existing firmware).

## Messages (brain → Mac)

### `heartbeat`

Sent every ~2 seconds. This is the Mac app's *only* signal that a brain is actually on
the other end of the serial line — there's no clean USB CDC "connected" event to hook on
the firmware side with plain Arduino `Serial`, so "have I seen a heartbeat in the last
few seconds" stands in for a connection state.

```json
{"type":"heartbeat","firmware":"0.4.0","activeProfile":0,"profileName":"Default"}
```

### `companion_action`

Sent whenever a mapping whose action type is `ACTION_COMPANION` fires — either from a
physical module event, or from the brain executing a stored mapping via `/api/trigger`.

```json
{"type":"companion_action","requestId":123,"subtype":"openApp","payload":"Spotify"}
```

`subtype` is one of:
- `openApp` — `payload` is the app's display name, e.g. `"Spotify"`
- `runShortcut` — `payload` is the Shortcut's name, e.g. `"Focus Mode"`
- `runAppleScript` — `payload` is literal AppleScript source, e.g.
  `"tell application \"Finder\" to activate"`

`requestId` is a monotonically increasing counter the brain assigns per companion
action fired. Not used for anything in v1 (fire-and-forget) — reserved so a future
`result` message from the Mac (see below) can reference which request it's reporting on.

## Messages (Mac → brain) — not implemented in v1

Deliberately deferred rather than half-built: a `result` message
(`{"type":"result","requestId":123,"ok":true}`) would let the brain show "Opened
Spotify" on its LCD the way `lastEventLabel` already works for HID actions. Skipped for
now to keep the first version fire-and-forget and testable without needing the Mac side
built first.

## Why reuse `modifier`/`str` on the existing `HIDAction` struct instead of new fields

When `type == ACTION_COMPANION`:
- `modifier` holds the subtype as a plain integer (`0 = openApp`, `1 = runShortcut`,
  `2 = runAppleScript`) — this byte is otherwise CTRL/SHIFT/ALT/GUI bitflags, meaningless
  for a companion action, so it's free to repurpose.
- `str` holds the payload text (app name / shortcut name / script source).
- `keycode` is unused (0).

This avoids growing the `Mapping`/`HIDAction` struct at all, which matters because its
size multiplies by `MAX_PROFILES × MAX_MAPPINGS` (8 × 48) in both NVS flash and the JSON
API responses.

`HIDAction.str` was bumped from 20 to 64 characters to comfortably fit app/shortcut
names and short one-line AppleScript commands — full multi-line scripts still won't fit
and aren't a v1 goal. This does change the `Mapping` struct's in-memory/on-flash size,
so a freshly flashed device starts with default profiles rather than trying to migrate
old saved data — a non-issue right now since nothing's been deployed to real hardware
yet.
