import QtQuick

import "../services" as Services

// VolumeIcon — the volume widget's PRESENTATION, in one place (ticket 11).
//
// WHY THIS IS A SHARED COMPONENT AND NOT A PROPERTY ON THE WIDGET
//
//   docs/adr/0001 says a service never decides what something looks like: the
//   decision belongs to the widget that draws it. AudioService used to publish
//   a glyph property, which was that decision living in the wrong place, and it
//   is gone from there now.
//
//   But "move it to the widget" is not the only question — it is "move it to
//   the widget" versus "move it to a third place, which is neither a service
//   nor a widget". Three consumers need this exact decision: the bar widget, the
//   volume OSD, and the pre-rewrite module that smoke.qml still instantiates
//   until ticket 18 deletes it. Three copies of a glyph table would drift the
//   moment the theme changed, which is the fourth failure mode ADR 0001 lists
//   and the reason this file exists.
//
//   So this is a component, not a service: it reads service STATE and produces
//   a DISPLAY ANSWER, it imports no palette, and the widget decides how to use
//   it. `color` is deliberately NOT here — a colour is a palette decision, and
//   this file cannot read shell/ui without becoming presentation for something
//   else to consume blindly. The widget applies UI.Colors itself.
//
//   What this is NOT: a service, a singleton, or anything whose state survives
//   a reload. It is created by whoever draws a volume, which is why there are
//   three of them rather than one.

QtObject {
    id: icon

    // ---- state, read from the service (and only state) --------------------
    readonly property var output: Services.AudioService.output

    // A sink that has not answered yet is a real state, not an error: pipewire
    // takes a moment to report a default output, and a widget instantiated in
    // that window must render something rather than throw.
    readonly property bool ready: icon.output.defaultSink !== null
        && icon.output.defaultSink !== undefined
        && icon.output.defaultSink.ready === true

    readonly property int volume: icon.output.volume
    readonly property bool isMuted: icon.output.isMuted
    readonly property bool isBluetooth: icon.ready && icon.output.isBluetooth
    readonly property string deviceFormFactor: icon.ready ? icon.output.deviceFormFactor : ""
    readonly property string deviceName: icon.ready ? icon.output.defaultSink.description : ""

    // Muted and "already at nothing" are different facts that want the same
    // glyph. Kept apart here because only one of them is worth reporting to the
    // user, and conflating them is how a widget ends up saying "Muted" for a
    // volume the user never silenced.
    readonly property bool silent: icon.ready && (icon.isMuted || icon.volume === 0)
    readonly property bool muted: icon.ready && icon.isMuted

    // ---- the four cases, in the order a user judges them --------------------
    //
    // The DECISION is a pure function of four facts, and it is factored out of
    // the properties on purpose. Two reasons, and the second is the real one:
    //
    //   * it reads as what it is — a decision, not a reading of a device — so a
    //     service (which must not decide appearance at all) could not host it;
    //   * it can be ASKED about a hardware combination this machine does not
    //     have. The promise is "the icon distinguishes headphones, handsets and
    //     speakers", and on a laptop with built-in speakers only the speaker
    //     branch would ever run — so the other two branches would never be
    //     exercised, on this machine or on any other single-output one. Asking
    //     the pure function directly is what makes the promise testable at all.
    //
    //   glyphFor(formFactor, percent, muted, ready)
    //     1. no device yet          → a placeholder glyph
    //     2. muted, or volume 0     → the muted glyph
    //     3. headphones / headset   → the headphone glyph at EVERY volume
    //     4. handset / speaker      → the speaker glyph, one to three waves by
    //                                  volume band
    //
    // Case 3 is the spec's promise that the indicator distinguishes
    // "headphones, handsets and speakers so the icon matches my hardware". A
    // speaker glyph at 40% on a pair of headphones is accurate and useless: the
    // icon is what the user looks at to answer "am I on the right output", and
    // form factor is the only input that answers it.
    //
    // `car` is kept from the pre-rewrite service because it was there: a car
    // head unit is a real form factor pipewire reports, and dropping it would
    // have made this a regression for anyone whose machine reports one.
    function glyphFor(form: string, percent: int, isMuted: bool, deviceReady: bool): string {
        if (!deviceReady) {
            return "󰓃"
        }
    // Case 2 is the pre-rewrite service's own mute: U+EE88, kept verbatim so
    // the icon the user already recognises is not silently swapped. (The
    // other glyphs are F025 / F095 / F1B9 for device and F026/F027/F028 for
    // the speaker waves — the same set, checked against literals in
    // verify-panels.sh, so none of them can drift unnoticed.)
        if (isMuted || percent === 0) {
            return "\uEE88"
        }
        if (form === "headphone" || form === "headset") {
            return "\uF025"
        }
        if (form === "phone" || form === "portable") {
            return "\uF095"
        }
        if (form === "car") {
            return "\uF1B9"
        }
        if (percent <= 33) {
            return "\uF026"
        }
        if (percent <= 66) {
            return "\uF027"
        }
        return "\uF028"
    }

    // The same decision, bound to THIS machine's state.
    readonly property string glyph: icon.glyphFor(
        icon.deviceFormFactor, icon.volume, icon.isMuted, icon.ready)

    // The Bluetooth mark. A SEPARATE glyph, not part of `glyph`, because the
    // speaker glyph's waves carry the level and overprinting a badge on them
    // destroys the information they were there to give.
    readonly property string bluetoothGlyph: "󰂯"

    // ---- the words, for a status line --------------------------------------
    //
    // The bands the pre-rewrite panel used, kept verbatim: they were chosen for
    // this shell's users and there is no reason to re-pick them in the move.
    // Presentational, so here rather than in the service.
    readonly property string statusLine: {
        if (!icon.ready) {
            return "waiting for a device"
        }
        if (icon.isMuted) {
            return "Muted"
        }
        if (icon.volume === 0) {
            return "Silenced"
        }
        if (icon.volume < 15) {
            return "Whisper"
        }
        if (icon.volume < 30) {
            return "Murmur"
        }
        if (icon.volume < 50) {
            return "Easy Listening"
        }
        if (icon.volume < 70) {
            return "Steady Groove"
        }
        if (icon.volume < 85) {
            return "Cranked Up"
        }
        if (icon.volume < 100) {
            return "Party Mode"
        }
        return "Concert Hall"
    }

    // One comparable line, so a reader of a log can tell which branch was taken
    // rather than having to trust that a glyph implies a case.
    function describe(): string {
        return "ready=" + icon.ready
            + " volume=" + icon.volume
            + " muted=" + (icon.isMuted ? "yes" : "no")
            + " form=\"" + icon.deviceFormFactor + "\""
            + " bluetooth=" + (icon.isBluetooth ? "yes" : "no")
            + " glyph=\"" + icon.glyph + "\""
            + " status=\"" + icon.statusLine + "\""
    }
}