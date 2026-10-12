import QtQml
import QtQuick
import Quickshell

import "."
import "../ui" as UI

// ClockWidget — time and date (ticket 06).
//
// The first widget on the contract, and the one the contract's optionality is
// easiest to check against: a clock has no panel, so it declares NO panelContent
// at all. It does not pass an empty Component. `hasPanel` therefore reads false
// for free, which is the point — a widget that has nothing to offer says
// nothing, and the shell learns that from the absence rather than from a value
// it had to be taught to ignore.
//
// It also has no click action of its own to offer, so `activate` is an explicit
// no-op rather than an unimplemented-looking gap: the contract requires every
// widget to declare one, and declaring "this widget does nothing on click" is
// the honest answer for a clock. (A future calendar panel would replace it.)
//
// It extends BarWidget directly rather than SimpleBarWidget because its content
// is a time, a rule and a date — not one label — so this is not a trivial
// label-plus-click widget.
BarWidget {
    id: clock

    // A clock's tooltip is the thing the bar does not already show: the date in
    // full. Overridden here rather than inherited, because the contract's
    // default would be wrong for it.
    tooltip: Qt.formatDate(systemClock.date, "dddd, d MMMM yyyy")

    // Declared, because the contract requires every widget to supply it.
    activate: function (widget) {}

    // ---- the time ---------------------------------------------------------
    //
    // SystemClock with Minutes precision is the whole mechanism: it re-reads the
    // system time at that granularity, so the clock cannot show a stale time.
    // Not a Timer polling Date.now() — that is the pattern that drifts and
    // needs a drift-correction nobody writes.
    SystemClock {
        id: systemClock
        precision: SystemClock.Minutes
    }

    // The cadence is READ BACK OFF the live SystemClock rather than restating
    // the literal above, so it reports what the widget actually does: change
    // `precision` to Seconds and this reports Seconds, and the check fails.
    // A hardcoded "Minutes" here would pass no matter what the clock did.
    readonly property string clockCadence: systemClock.precision === SystemClock.Minutes
        ? "Minutes"
        : (systemClock.precision === SystemClock.Seconds ? "Seconds"
            : (systemClock.precision === SystemClock.Milliseconds ? "Milliseconds" : "UNKNOWN"))

    // Time follows the user's locale, so the shell reads the way their machine is
    // configured rather than imposing one. `Locale.ShortFormat` is the correct
    // spelling on this build: Qt.TimeFormat does NOT exist (the v0.3.0 docs and
    // habit suggest it), and using it fails at RUN time with "Cannot read
    // property 'ShortFormat' of undefined" — which is exactly the class of
    // failure the smoke log check exists to catch. Locale lives in QtQml.
    //
    // ---- the time format option (ticket 09) --------------------------------
    //
    // The clock's own option, and the demonstration that a widget can be tuned
    // without a code change:
    //
    //     { "type": "clock", "timeFormat": "long" }
    //
    // Three widget-level properties to declare and read one option, which is
    // the whole of the mechanism — the delivery, the default and the reporting
    // all live on the contract (BarWidget), so nothing below is clock-specific.
    //
    // DECLARED BY ASSIGNMENT, NOT BY RE-DECLARATION. `optionDefaults` is
    // inherited from BarWidget, and a derived QML type cannot re-declare or
    // override a property its base already has; it must be ASSIGNED. Writing
    // `readonly property var optionDefaults: …` here instead silently does
    // nothing — see the note in BarWidget.
    optionDefaults: ({ "timeFormat": "short" })

    // What the widget settled on. Read through optionValue, so an entry that
    // says nothing leaves this at the declared default — which is what makes
    // `{ "type": "clock" }` (the ticket-07 format, no options at all) render
    // exactly as it did before this option existed.
    readonly property string timeFormat: clock.optionValue("timeFormat")

    // The locale pattern this option selected, reported so the shell can be
    // told which of the two it is really using rather than being asked to
    // trust the option's name.
    // `Locale.ShortFormat` / `Locale.LongFormat` are read inline rather than
    // held in named constants: a QML property name cannot begin with an upper
    // case letter, so the obvious spelling for a constant here (`LONG_FORMAT`)
    // does not compile at all — it is a load error, not a lint. See
    // quickshell-api-notes.md.
    readonly property var timeFormatPattern: clock.timeFormat === "long"
        ? Qt.locale().timeFormat(Locale.LongFormat)
        : Qt.locale().timeFormat(Locale.ShortFormat)

    // Any value other than the two named ones falls back to the default rather
    // than being passed to Qt.formatTime(). That is deliberate and it is the
    // ONLY validation this widget does: an unusable VALUE is a different
    // failure from an unknown KEY, and it costs the user their chosen format,
    // never a thrown exception out of a formatting call. `unrecognisedOptions`
    // (the contract) reports unknown keys; a known key with a nonsense value
    // is this widget's own business, and the shell has no vocabulary for it.
    // A third format is a later ticket, not a guess made here.
    readonly property var shortDateFormat: Qt.locale().dateFormat(Locale.ShortFormat)

    readonly property string timeText: Qt.formatTime(systemClock.date, clock.timeFormatPattern)
    // Numeric short date (e.g. 12/10/2026) — the tooltip below carries the long
    // human form, so the two together say the same thing at two resolutions.
    readonly property string dateText: Qt.formatDate(systemClock.date, clock.shortDateFormat)

    // The content: time, a separator, then the date. Reads outside the content
    // Component so the bar can be told what the clock says without reaching
    // into the Loader.
    content: Component {
        Row {
            spacing: 6

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: clock.timeText
                color: UI.Colors.foreground
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSize
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: UI.Fonts.fontSize
                color: UI.Colors.foregroundMuted
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter

                text: clock.dateText
                color: UI.Colors.foregroundMuted
                font {
                    family: UI.Fonts.fontFamily
                    pixelSize: UI.Fonts.fontSize
                }
            }
        }
    }
}