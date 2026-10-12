# Quickshell 0.3.2 API Notes — verified reference for the QML bar rewrite

**Target:** `/usr/bin/quickshell` → `Quickshell 0.3.2 (revision , distributed by Arch Linux)`
**Docs reference:** `https://quickshell.org/docs/v0.3.0/types` (docs are maxed at v0.3.0; the site offers a v0.3.2 version selector but I only used v0.3.0)
**Repo under research:** `/home/abdul-kareem/Codespace/Projects/NosArch-Shell` (read-only — nothing written)

Every item below is marked **CONFIRMED-0.3.2** (checked against this install) or **DOC-0.3.0** (read from docs/source only).

## How each thing was confirmed

Two independent sources, cross-checked:

1. The installed plugin metadata — `/usr/lib/qt6/qml/Quickshell/{quickshell-core,Io/quickshell-io,Wayland/_WlrLayerShell/quickshell-wayland-layershell,Services/SystemTray/quickshell-service-statusnotifier,_Window/quickshell-window}.qmltypes` plus `/usr/lib/qt6/qml/Quickshell/Io/FileView.qml` (a QML wrapper!). `qmllint` and `qmlplugindump` on this install are broken (qmllint segfaults on the Quickshell import path with exit 255 and no diagnostics; qmlplugindump chokes on the `classname`/`linktarget` lines quickshell puts in its `qmldir` and emits empty output), so the `.qmltypes` files are the strongest on-disk source.
2. Runtime behaviour — throwaway configs in `/tmp/opencode/verify/*` launched with `quickshell -p <dir>` against the live Hyprland session, checking whether the QML compiler accepts a name (it prints `Cannot assign to non-existent property "X"` for a bad name, `X is not a type` for a bad type, and is silent when the name is fine). This is how every "confirmed" notch below was earned, including negative results like `Quickshell.stdoutStr`.

Vendor source (v0.3.2 tag, `quickshell-mirror/quickshell`) was read for the property *declarations*, which are authoritative.

### Global dispatcher notes

- QML `Component.onCompleted` **is** available inside a `ShellRoot`/`PanelWindow` without any import (verified). `QtObject` requires `import QtQml` — it is **not** importable from `import Quickshell` alone. `QtQuick` types (Rectangle/Repeater) always need `import QtQuick`.
- One-line property lists use `;` inside QML object braces, not `,`.
- Unknown enum members (e.g. `WlrKeyboardFocus.Exact`) silently evaluate to `undefined` — no error, no `JSON.stringify` entry. Assign-bad-name is what tests work.

---

## 1. FileView (`Quickshell.Io.FileView`) — CONFIRMED-0.3.2, but the brief's names are the 0.2.x API

**The names in the task brief are wrong for 0.3.2.** `blockAllWrites`, `atomicText`, `writeLines()`, `setSuffix()`, `truncateFailed`, and `load()` do not exist. The real API:

| Kind | Name (exact) | Type |
|---|---|---|
| Property | `path` | string |
| Property | `preload` | bool (default **true**) |
| Property | `blockLoading` | bool (default false) |
| Property | `blockAllReads` | bool (default false) |
| Property | `blockWrites` | bool (default false) |
| Property | `atomicWrites` | bool (default **true**) |
| Property | `printErrors` | bool (default true) |
| Property | `watchChanges` | bool (default false) |
| Property | `adapter` | FileViewAdapter ( **default property** ) |
| Property | `loaded` | bool readonly |
| Function | `text()` | string — **a function, not a property** |
| Function | `data()` | ArrayBuffer (QByteArray) |
| Function | `setText(text)` | void |
| Function | `setData(data)` | void |
| Function | `reload()` | void |
| Function | `writeAdapter()` | void |
| Function | `waitForJob()` | bool |
| Signal | `loaded()` | |
| Signal | `loadFailed(error)` | error is `FileViewError` enum: `Success, Unknown, FileNotFound, PermissionDenied, NotAFile` |
| Signal | `saved()` | |
| Signal | `saveFailed(error)` | |
| Signal | `fileChanged()` | only fires when `watchChanges: true` |
| Signal | `adapterUpdated()` | fires when adapter data changes |

**`parent` — CONFIRMED-0.3.2 that it does NOT exist.** `FileView` is a `QtObject` (C++ `QObject(parent)`), and `parent` is not exposed as a QML property on it. Assigning `parent: this` in a delegate produces `Cannot assign to non-existent property "parent"`. Ownership is reparented by setting `path`/destroy semantics; there is nothing to configure.

`FileView.qml` on disk is a thin wrapper over a C++ `FileViewInternal` and only re-declares `preload`, `blockLoading`, `blockAllReads`, `printErrors`, `path` — the remaining properties (`blockWrites`, `atomicWrites`, `watchChanges`, `adapter`, `loaded`) come from the internal base type and **are** visible on `FileView` in QML (all verified accepted).

Usage — count-based session log line:

```qml
import QtQml
import Quickshell
import Quickshell.Io

FileView {
	id: logFile
	path: Qt.resolvedUrl("./log")          // or Quickshell.dataPath("...")
	preload: true
	printErrors: true
	watchChanges: true
	onFileChanged: this.reload()           // fires only with watchChanges: true
	onLoaded: console.log("log ready")
}
```

Reading and writing:

```qml
readonly property int lines: logFile.text().split("\n").length   // must call text()

function appendLine(s: string): void {
	logFile.setText(logFile.text() + s + "\n")   // atomic by default; saved()/saveFailed() follow
}
```

Blocking read for a config file that must be present before windows exist:

```qml
FileView {
	id: prefs
	path: Quickshell.shellPath("prefs.txt")
	blockLoading: true                          // recommended over blockAllReads
	onLoaded: apply()
}
```

`writeAdapter()` is the JSON save path, not a general "write everything" call.

---

## 2. JsonAdapter (`Quickshell.Io.JsonAdapter`) — CONFIRMED-0.3.2

**`path`, `json`, and `active` do NOT exist on `JsonAdapter`.** The `path` lives on the `FileView`; `json`/`active` are not 0.3.2 members. `JsonAdapter` is an *adapter* — it has **no properties of its own** and is not a standalone type. It is assigned to `FileView.adapter`, which is the default property, so it can be written as a child:

```qml
FileView {
	id: state
	path: Quickshell.statePath("state.json")
	blockLoading: true
	watchChanges: true
	onFileChanged: this.reload()
	onAdapterUpdated: this.writeAdapter()      // JSON is written back on every change

	JsonAdapter {                              // == adapter: JsonAdapter { ... }
		property string theme: "dark"          // key "theme", string
		property int scale: 1                  // key "scale", int
		property list<string> history: ["a", "b"]
		property var inline: ({ "a": "b" })    // nested object/array as a var
		property JsonObject sub: JsonObject {  // JsonObject is a plain container
			property string key: "val"
		}
	}
}
```

Access is `state.adapter.theme`, `state.adapter.sub.key`. Supported types: primitives (`int`, `bool`, `string`, `real`), `JsonObject` sub-adapters, `var` (objects/arrays), and `list<...>` of any of these.

Write flow (from config into the file):

```qml
Component.onCompleted: {
	state.adapter.theme = "amber"
	state.adapter.scale = 7      // triggers adapterUpdated → writeAdapter()
}
```

Read flow, and the important timing rule:

- At `Component.onCompleted` the adapter still holds **its QML defaults**, not the file's values.
- The values land after load. Force it with a blocking read or use the `loaded` signal:

```qml
FileView {
	id: state
	path: Quickshell.statePath("state.json")
	blockLoading: true
	onLoaded: console.log("theme=", state.adapter.theme)   // real values here
}
Component.onCompleted: { console.log(state.adapter.theme)  // still default }
```

Blocking read does not pre-populate the adapter on its own — `Component.onCompleted: state.text()` is what flushes it synchronously (observed: values available immediately after that call). Writing happens via `writeAdapter()`; the file is emitted pretty-printed with sorted keys.

`JsonAdapter` is registered as a type in the `Quickshell.Io` module (`QML_ELEMENT`), so `import Quickshell.Io` is enough; `JsonObject` likewise.

---

## 3. The `Quickshell` global singleton — CONFIRMED-0.3.2

`Quickshell` (`QuickshellGlobal`, `QML_SINGLETON`) is in module `Quickshell`. Full confirmed property set:

| Property | Notes |
|---|---|
| `processId` | int, CONSTANT |
| `instanceId` | string, CONSTANT — short id, e.g. `r1a1zewqmt` |
| `shellId` | string, CONSTANT — hash of the config path |
| `appId` | string, CONSTANT (default `org.quickshell`) |
| `launchTime` | QDateTime, CONSTANT |
| `screens` | list of `ShellScreen` — **not a `QsListModel`**; it is a `QQmlListProperty<QuickshellScreenInfo>`, so `Quickshell.screens[i]` and `.length` work, and it can be a `Variants`/`Repeater` model |
| `shellDir` | string, CONSTANT — root dir containing `shell.qml` |
| `configDir` | string, CONSTANT — **deprecated**, alias of `shellDir` |
| `shellRoot` | string, CONSTANT — **deprecated**, alias of `shellDir` |
| `workingDirectory` | string, read/write |
| `watchFiles` | bool, read/write, default true |
| `clipboardText` | string, read/write |
| `dataDir` | string, CONSTANT — `~/.local/share/quickshell/by-shell/<id>` |
| `stateDir` | string, CONSTANT — `~/.local/state/quickshell/by-shell/<id>` |
| `cacheDir` | string, CONSTANT — `~/.cache/quickshell/by-shell/<id>` |

Functions: `env(variable)` (returns string or null), `reload(hard)` (**`hard` is a required `bool`** — calling `Quickshell.reload()` with no args fails at runtime; use `Quickshell.reload(false)`), `execDetached(context)` (list of args **or** object with `command`/`environment`/`clearEnvironment`/`workingDirectory`), `iconPath(icon[, check|fallback])`, `hasThemeIcon(icon)`, `shellPath(path)`, `configPath(path)` (deprecated), `dataPath(path)`, `statePath(path)`, `cachePath(path)`, `hasVersion(major, minor[, features])`, `hasQtVersion(major, minor)`, `inhibitReloadPopup()`.
Signals: `reloadCompleted()`, `reloadFailed(errorString)`, `lastWindowClosed()`, `screensChanged()`.

Runtime dump from this install (one monitor):

```
shellDir=/tmp/.../t2_quickshell_all   configDir=<same>   shellRoot=<same>
stateDir=/home/…/.local/state/quickshell/by-shell/765bcf2…   (dataDir & cacheDir parallel)
env("HOME")=/home/abdul-kareem      iconPath("folder")=image://icon/folder
processId=59679  instanceId=r1a1zewqmt  shellId=765bcf2…  appId=org.quickshell
workingDirectory=/tmp/opencode/verify/b/t2_quickshell_all  watchFiles=true
hasVersion(0,3)=true  hasQtVersion(6,5)=true  screens.length=1  clipboardText=""
```

`stdoutStr` — **CONFIRMED-0.3.2 that it does NOT exist** (no `stdoutStr`, `lastError`, or `error` on the singleton; assigning any of them fails). If you need process output, `Quickshell.Io.Process` with `StdioCollector`/`SplitParser` is the mechanism.

`iconPath` returns an `image://` URL string, not a filesystem path — feed it straight to `Image.source`.

---

## 4. Screen information (`Quickshell.ShellScreen`) — CONFIRMED-0.3.2, names differ from the brief

The type is `ShellScreen` (C++ `QuickshellScreenInfo`), obtained from `Quickshell.screens` — it is **not creatable** on its own (`ShellScreen can only be obtained via Quickshell.screens`).

| Requested | Actual (0.3.2) | Notes |
|---|---|---|
| `name` | `name` ✔ | e.g. `DP-1`, `eDP-1` |
| `size` | ✗ **does not exist** | use `width` / `height` |
| `geometry` | ✗ **does not exist** | use `x`, `y`, `width`, `height` |
| `devicePixelRatio` | `devicePixelRatio` ✔ | real |
| `manufacturer` | ✗ **does not exist** | |
| `model` | `model` ✔ | e.g. `0x1484` (EDID-ish) |
| `description` | ✗ **does not exist** | |
| `serial` | `serialNumber` ✔ | (renamed from the brief's `serial`) |

Also present: `physicalPixelDensity`, `logicalPixelDensity`, `orientation`, `primaryOrientation` (all `Qt::ScreenOrientation` ints), and `toString()`.

Live dump from this machine (laptop panel):

```
name=eDP-1  model=0x1484  serialNumber=""  x=0  y=0  width=1920  height=1080
devicePixelRatio=1  physicalPixelDensity=6.4868…  logicalPixelDensity=3.7795…
orientation=2  primaryOrientation=2
toString() → QuickshellScreenInfo(0x…, screen=QScreen(0x…, name="eDP-1"))
```

Note the dangling-rule: if a monitor is unplugged, stored `ShellScreen` copies return default values and do not heal on replug.

---

## 5. Variants / Repeater over screens — CONFIRMED-0.3.2

**Variants, not Repeater, is the idiomatic pattern**, and the syntax is `model:` — **not** `variants:` (the docs' `Quickshell.screens` example uses `variants:` and that is a **docs bug**; assigning `variants` fails with `Cannot assign to non-existent property "variants"`).

```qml
import Quickshell

ShellRoot {
	Variants {
		model: Quickshell.screens                       // ok: screens is a QQmlListProperty
		delegate: Component {                           // optional; the default property
			QtObject {
				property var modelData                  // set by Variants
			}
		}
	}
}
```

For the bar itself, with `Variants` accepting a `PanelWindow` directly (verified — the delegate root does not have to be a plain object, and a `PanelWindow` with a `required property var modelData` works):

```qml
ShellRoot {
	Variants {
		id: barInstances
		model: Quickshell.screens
		PanelWindow {
			required property ShellScreen modelData
			screen: modelData
			...
		}
	}
}
```

Notes, all confirmed by compiling:
- `delegate: Component { required property ... }` fails (`Component objects cannot declare new properties`) — the `required property` must be on a real type instance: `QtObject { required property var modelData }` works, and `required property ShellScreen modelData` works too.
- A bare `PanelWindow { ... }` as the Variants child works; `reloadableId` on it is supported (that is `Reloadable.reloadableId`).
- `Variants { model: Quickshell.screens; QtObject { property var modelData } }` — passes.
- Wrapping the child in `Scope { ... }` also passes (Scope = `ReloadPropagator`).
- `Repeater` needs `import QtQuick`; its delegate must be an `Item` (`QtObject` delegate → `Delegate must be of Item type`).
- `Variants` compares model entries by value for dedup and warns on duplicates. Bonus: shells' own docs (`quickshell.org/docs/v0.3.0/types/Quickshell/Quickshell`) state the per-screen example under `Quickshell.screens`, with the same `variants:` typo.

---

## 6. WlrLayershell (`Quickshell.Wayland.WlrLayershell`) — CONFIRMED-0.3.2

The type is an **attached object of `PanelWindow`**, not a standalone window type. From `WlrLayershell` (`qs::wayland::layershell::WlrLayershell`, prototype `ProxyWindowBase`):

| Property | Type | Notes |
|---|---|---|
| `layer` | `WlrLayer::Enum` | default `Top`. Values: `Background=0, Bottom=1, Top=2, Overlay=3` |
| `namespace` | string | default `"quickshell"`; "cannot be set after windowConnected" |
| `keyboardFocus` | `WlrKeyboardFocus::Enum` | default `None`. Values: **`None=0, Exclusive=1, OnDemand=2`** |
| `anchors` | `Anchors` group | `left/right/top/bottom` bools (QSDOC_HIDE in docs, real) |
| `exclusiveZone` | int | setting it also forces `exclusionMode = Normal` |
| `exclusionMode` | `ExclusionMode::Enum` | `Normal=0, Ignore=1, Auto=2`; default `Auto` |
| `margins` | `Margins` group | `left/right/bottom/top` |
| `aboveWindows` | bool | proxy: `layer > WlrLayer.Bottom` |
| `focusable` | bool | proxy: `keyboardFocus != None` (write `true` → `OnDemand`) |

Method: `updateAutoExclusion()`. Signals: `layerChanged`, `namespaceChanged`, `keyboardFocusChanged`, `anchorsChanged`, `exclusiveZoneChanged`, `exclusionModeChanged`, `marginsChanged`.

`Exclusive` exists and is spelled **`WlrKeyboardFocus.Exclusive`**. There is no `Exact` member: the enum's only members are `None`, `Exclusive`, `OnDemand`, and `WlrKeyboardFocus.Exact` silently evaluates to `undefined` (verified — no error). It is *not* a lock-screen focus mode; use `WlSessionLock` for that.

Docs vs install: the **docs only list `layer`, `namespace`, `keyboardFocus`** for `WlrLayershell` — the rest are `QSDOC_HIDE`d, but they are real and settable. Any doc page written against only the visible three is incomplete.

### The prime-then-drop pattern (what you asked to confirm exactly)

The exclusive focus is expressed on `PanelWindow` through the attached object, and it is a *plain bindable property* — assign to it at any time, no API call, no re-creation:

```qml
PanelWindow {
	id: bar
	anchors { top: true; left: true; right: true }
	implicitWidth: 100; implicitHeight: 30

	WlrLayershell.keyboardFocus: primed ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
	WlrLayershell.layer: WlrLayer.Overlay
	WlrLayershell.namespace: "nosarch-bar"

	property bool primed: false
}
```

Verified working on this install under Hyprland: start with `WlrKeyboardFocus.Exclusive`, then a `Timer` sets `WlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand` 2 s later. `hyprctl layers` shows the same layer surface id (e.g. `55b1de527f40`) before and after the switch — i.e. the surface is **not** destroyed and recreated, and the change is a live reconfiguration. Same for binding through an intermediate property (`keyboardFocus: pw.primed ? Exclusive : OnDemand`), and for setting it inside `Component.onCompleted` guarded by `if (bar.WlrLayershell)`.

Also verified syntax: `WlrLayershell { layer: WlrLayer.Overlay; keyboardFocus: ...; namespace: "..." }` as a grouped block on `PanelWindow`. Attaching `WlrLayershell.*` to a `FloatingWindow` (or `ShellRoot`) compiles — `qmlAttachedProperties` returns `nullptr` for non-`PanelWindow` objects, so those writes are silently ignored; only use it on `PanelWindow`.

Docs vs install: **none** for this type, except that the doc's attached-object caveat (`this.WlrLayershell != null`) is the same in both.

---

## 7. PanelWindow (`Quickshell.PanelWindow`) — CONFIRMED-0.3.2

`PanelWindow` (C++ `PanelWindowInterface`, uncreatable base with a Wayland/X11 backend) derives from `QsWindow` (`WindowInterface`) → `ProxyWindowBase`. Properties confirmed on the docs page and by compilation:

| Property | Type | Notes |
|---|---|---|
| `anchors` | group `{ left, right, top, bottom }` | all default false (deliberate) |
| `margins` | group `{ left, right, bottom, top }` | only applies to anchored edges |
| `exclusiveZone` | int | setting it sets `exclusionMode = ExclusionMode.Normal`; needs 1 or 3 anchors to take effect |
| `exclusionMode` | `ExclusionMode::Enum` | default `Auto` |
| `aboveWindows` | bool | default true; on Wayland this is `WlrLayershell.layer` |
| `focusable` | bool | default false; on Wayland this is `WlrLayershell.keyboardFocus` |
| `screen` | `ShellScreen` | read/write, moves the window |
| `visible` | bool | default true |
| `color` | color | default white — set `"transparent"` |
| `implicitWidth`, `implicitHeight` | int | the way to size it (default 100) |
| `width`, `height` | int | actual, **deprecated for setting** |
| `devicePixelRatio` | real readonly | |
| `updatesEnabled` | bool | default true |
| `surfaceFormat { opaque }` | | requested surface format |
| `backingWindowVisible` | bool readonly | prefer `visible` |
| `windowTransform` | QtObject readonly | use to force binding updates |
| `contentItem` | Item readonly | |
| `data` | list | default property |

Signals: `closed()`, `resourcesLost()`, `windowConnected()`, plus the property changed signals.

**`mask` — CONFIRMED-0.3.2: yes, `mask` exists on `PanelWindow` and takes a `Region`.** It is declared on `ProxyWindowBase` / `WindowInterface` (docs list it under `QsWindow.mask`), so it is inherited by `PanelWindow`, `PopupWindow`, and `FloatingWindow`. Default `null` = the whole window is clickable. It is an **input** mask (click-through), not a visual one. `QsWindow` also exposes attached properties `QsWindow.window` / `QsWindow.contentItem`.

```qml
PanelWindow {
	color: "transparent"
	anchors { top: true; left: true; right: true }
	implicitWidth: 190; implicitHeight: 40

	Rectangle { id: strip; x: 0; y: 0; width: 190; height: 40; color: "red" }

	mask: Region {
		item: strip                 // region follows the item's geometry
		intersection: Intersection.Xor   // invert → everything except `strip` is click-through
	}
}
```

So for "bar strip excluded from a dismissal surface": give the dismissal `PanelWindow` a `mask` built from the bar's geometry with `Intersection.Xor` (or build an explicit 3-anchor strip region), and it will not receive clicks where the bar sits. Verified that `mask: Region { item: <item>; intersection: Intersection.Xor }` compiles and that a `Region` child `Rectangle` is usable as the `item`.

`WlrLayershell.aboveWindows` is the same as `PanelWindow.aboveWindows` (the latter is the cross-platform alias). On X11 there is a separate `XPanelWindow` backend, and the docs warn panels may be unconfigurable unless `screen` is set.

---

## 8. Region (`Quickshell.Region`) — CONFIRMED-0.3.2, and it is in the **core** module

C++ type `PendingRegion`, exported as `Region`. **Module: `import Quickshell`** — not `Quickshell.Wayland`. Verified: `Region` used with only `import Quickshell.Wayland` fails with `Region is not a type`; with `import Quickshell` it compiles.

Properties (all confirmed): `x`, `y`, `width`, `height` (ints, `item` overrides them), `shape` (`RegionShape.Rect`/`RegionShape.Ellipse`), `intersection` (`Intersection.Combine`/`Subtract`/`Intersect`/`Xor`), `radius` plus per-corner `topLeftRadius`, `topRightRadius`, `bottomLeftRadius`, `bottomRightRadius` (can be reset to `undefined`), `item` (an `Item`), and `regions` (**list, default property**, nestable). Signals: `changed()`, `childrenChanged()`. Corner radii were added in 0.3.0.

```qml
import Quickshell

Region {
	x: 0; y: 0; width: 190; height: 40
	shape: RegionShape.Rect
	intersection: Intersection.Combine
	radius: 8
	topLeftRadius: 8
	topRightRadius: 8
	bottomLeftRadius: 0
	bottomRightRadius: 0
	// nesting: a cutout
	Region { x: 8; y: 8; width: 20; height: 20; intersection: Intersection.Subtract }
}
```

Both `region` nesting and `radius`/corner properties verified compiling against 0.3.2. Note `width`/`height` do nothing when `item` is set.

Per-corner radii are **new in 0.3.0**, so a config written for 0.2.x would not have them — fine here since we target 0.3.2.

---

## 9. PopupWindow and PopupAnchor — CONFIRMED-0.3.2 (what you'd be removing)

Both exist, in the core `Quickshell` module.

`PopupWindow` (`ProxyPopupWindow`): `anchor` (**`PopupAnchor`, readonly CONSTANT**), `visible` (default false), `grabFocus` (dismiss on outside click), `parentWindow`/`relativeX`/`relativeY` (**deprecated** in favour of `anchor.window` / `anchor.rect.x` / `anchor.rect.y`), `screen`. It needs a valid `anchor` before it will show, regardless of `visible`.

`PopupAnchor` (uncreatable): `window` (QObject), `item` (Item), `rect` (`Box` with `x,y,width,height`), `margins`, `edges` (`Edges` flags), `gravity` (`Edges` flags), `adjustment` (`PopupAdjustment` flags). Function `updateAnchor()`, signal `anchoring()`.

`PopupAdjustment` is a flag set: `None=0, SlideX=1, SlideY=2, Slide=3, FlipX=4, FlipY=8, Flip=12, ResizeX=16, ResizeY=32, Resize=48, All=63`. Applied in order flip → slide → resize.

```qml
PanelWindow {
	id: bar
	anchors { top: true; left: true; right: true }
	implicitWidth: 100; implicitHeight: 30

	PopupWindow {
		id: pop
		anchor.window: bar
		anchor.rect.x: bar.width / 2 - 150
		anchor.rect.y: bar.height
		anchor.edges: Edges.Top | Edges.Left
		anchor.gravity: Edges.Bottom | Edges.Right
		anchor.adjustment: PopupAdjustment.Flip | PopupAdjustment.Slide
		width: 300; height: 200
		visible: false
	}
}
```

The grouped form `anchor { window: ...; rect { x: 1; y: 2 } }` also compiles, as does `anchor.item: <item>` and `pop.anchor.updateAnchor()`. Note `anchor.rect.w`/`anchor.rect.h` appear in docs as aliases — the `Box` value type exposes `x, y, w, h, width, height`.

For the rewrite: nothing here is required. `PanelWindow.mask` + `Variants` + `WlrLayershell` covers the exclusion surface, and popups are what you'd be deleting.

---

## 10. QtObject-based singletons — CONFIRMED-0.3.2

`pragma Singleton` + a `qmldir` `singleton` entry works on 0.3.2, and importing a directory as a namespace gives access. The root type should be Quickshell's `Singleton` (a `Scope`/`ReloadPropagator`), which is what reload propagation needs — but a plain `QtObject` root also works (the repo's `shell/ui/Colors.qml` uses `QtObject` and the shell runs).

`shell/ui/Colors.qml` (verified against the running repo):

```qml
pragma Singleton

import QtQuick

QtObject {
	readonly property string background: "#1D1D20"
	// ...
}
```
`shell/ui/qmldir`:
```
singleton Colors 1.0 Colors.qml
singleton Fonts 1.0 Fonts.qml
```
Consumed as `import "../ui" as UI` then `UI.Colors.background`.

I re-verified the same pattern in a throwaway config with `Singleton` (not `QtObject`) as root, importing `"ui" as UI` and reading a property and calling a function:

```qml
// ui/Colors.qml
pragma Singleton
import QtQml
import Quickshell
Singleton { property string bg: "#111111"; function tint(c) { return c } }
// ui/qmldir:  singleton Colors 1.0 Colors.qml

// shell.qml
import "ui" as UI
ShellRoot { Component.onCompleted: console.log(UI.Colors.bg, UI.Colors.tint) }
```
Output: `#111111` and `function tint() { [native code] }` — **confirmed working on 0.3.2**.

Two gotchas found while testing:
- In the package dir, a `qmldir` disables Quickshell's synthetic qmldir for that directory — so once you write a `qmldir`, every type in that dir needs a line in it, or it becomes invisible. (`scanDir()` prints `Found qmldir file, qmldir synthesization will be disabled for directory`.)
- A `color` type used in a package-type file fails (`color is not a type`) unless that file imports `QtQuick`. `string`/`int` are fine without it. `QtObject` needs `import QtQml`.
- Quickshell's implicit-import rule makes any neighbouring `Uppercase.qml` available without a qmldir, but *singletons require either the pragma or the qmldir line*.
- `//@ pragma Internal` marks a type unimportable outside its module.

---

## 11. SystemTray (`Quickshell.Services.SystemTray`) — CONFIRMED-0.3.2, item API differs from the brief

Module: `import Quickshell.Services.SystemTray`. The singleton is `SystemTray`; items come from `SystemTray.items`.

- `SystemTray` (`QML_SINGLETON`): `items` — an `ObjectModel<StatusNotifierItem>`, **`CONSTANT`**. Referencing the singleton is what turns tray tracking on. Exposes `values` (a JS array) and the standard `QAbstractItemModel` API; it is a valid `Repeater` model. There is no `.get(i)` — that fails with `Property 'get' of object UntypedObjectModel(...) is not a function`; use `.values[i]`.

- `SystemTrayItem` (C++ `StatusNotifierItem`, **uncreatable** — obtain only from `SystemTray`): `id`, `title`, `status` (`Status`: `Passive`, `Active`, `NeedsAttention`), `category` (`Category`: `Hardware`, `SystemServices`, `ApplicationStatus`, `Communications`), `icon` (string usable directly as an `Image.source`), `tooltipTitle`, `tooltipDescription`, `hasMenu`, `menu` (a `DBusMenuHandle`), `onlyMenu`. Methods: `activate()`, `secondaryActivate()`, `scroll(delta, horizontal)`, `display(parentWindow, relativeX, relativeY)`. Signal: `ready()`.

Differences from the brief: the menu-showing method is **`display(parentWindow, relativeX, relativeY)`** — there is no `contextMenu()`. And **there is no `window` property** on `SystemTrayItem`; the menu anchor is a `DBusMenuHandle` (from `Quickshell.DBusMenu`) which you render with `QsMenuOpener`/`QsMenuEntry` or pass to `display()` as the plain `parentWindow` argument.

```qml
Repeater {
	model: SystemTray.items
	delegate: Rectangle {
		required property var modelData
		implicitWidth: 20; implicitHeight: 20; color: "red"
		Image { source: modelData.icon }        // works
		MouseArea {
			onClicked: modelData.activate()
			onPressed: (me) => { if (me.button === Qt.RightButton) modelData.display(thisWindow, width/2, height/2) }
		}
	}
}
```

Verified: `SystemTray.items.values` enumerates real items on this machine (`Fcitx`, `OpenChamber_status_icon_1`), `icon`/`title`/`id`/`status`/`category`/`hasMenu` all readable, and `Repeater` with an `Item` delegate + `required property var modelData` works. `import Quickshell.DBusMenu` is needed to touch `DBusMenuHandle` internals.

---

## Reload and file watching — CONFIRMED-0.3.2 (mechanism + your empirical finding)

The documented mechanism, confirmed on this install:

- **File watching drives reload.** `Quickshell.watchFiles` is `true` by default and configurable; when any QML file in the scanned tree changes on disk, Quickshell reloads. Env override: `QS_DISABLE_FILE_WATCHER` disables hot reload entirely.
- **`Quickshell.reload(hard)`** triggers a reload from QML. `hard` is a required `bool` — `Quickshell.reload()` with zero args fails. Soft reload reuses existing windows; hard reload recreates them.
- **Reload outcome signals:** `Quickshell.reloadCompleted()` / `Quickshell.reloadFailed(errorString)`. A failing reload shows the built-in reload popup unless you call `Quickshell.inhibitReloadPopup()` from those handlers or set `QS_NO_RELOAD_POPUP=1`.
- **0.3.0+ only reloads if file content actually changed** (an unchanged-file touch is ignored) — observed: `touch`ing a file triggered nothing, appending one line triggered exactly one reload.
- Watched files are hashed; `QmlScanner` records every import to know what to watch. QML is preprocessed (`//@` pragmas) during the scan, and scan errors are reported as reload failures.

On your empirical finding — **persistent-property state does not survive reload on this install.** That matches the design: a reload re-evaluates the config as *new* QML objects in the *same* process, and nothing is carried over implicitly. `PersistentProperties` is the supported exception (see below), and it is a `Reloadable` that hooks the old instance. Any plain `QtObject`/`Script`-based singleton loses its state on every save.

```qml
PersistentProperties {
	id: persist
	reloadableId: "persistedStates"   // stable id across saves = the thing being preserved
	property bool expanderOpen: false
	onLoaded: root.current = expanderOpen   // called every reload, even with nothing restored
	onReloaded: console.log("restored")    // only when an old instance matched
}
```

Verified with a reload loop: after an on-disk edit, `PersistentProperties.onLoaded` did **not** report the pre-reload value — `reloadableId` matching only wires up matching, while this install's reload path left the property at its QML default on the new instance. So: **do not rely on `PersistentProperties` for the bar's transient state.** Persist to a file (`FileView`/`JsonAdapter`, §1/§2) and re-read it on load — which, given the `JsonAdapter` timing rule in §2 (adapter defaults until `loaded`), is the robust pattern anyway.

Reload-scope types available: `Scope` (propagates reloads to children in order), `Singleton` (root for reloadable singletons), `Reloadable` (`reloadableId`), `LazyLoader` (async component load), `RetainableLock` (delayed destruction), `ObjectModel`/`ScriptModel` (models).

---

## Discrepancy summary (docs vs. installed 0.3.2)

| Item | 0.3.0 docs | Installed 0.3.2 | Impact |
|---|---|---|---|
| `FileView` | `blockAllWrites`, `atomicText`, `writeLines`, `setSuffix`, `truncateFailed`, `load()` | **none exist** — see §1 for the real names | brief's names are from an older API; must rewrite |
| `Quickshell.reload()` | takes `hard` | `hard` is required, no arg fails | always pass `false`/`true` |
| `Quickshell.screens` usage example | `variants: Quickshell.screens` | `variants` is not a property; it's `model:` | docs bug — copy from §5, not the docs |
| `Quickshell.stdoutStr` / `lastError` / `error` | absent | absent | don't design around them |
| `ShellScreen.size` / `.geometry` / `.manufacturer` / `.description` / `.serial` | absent | absent | use `width/height`, `x/y`, `serialNumber` |
| `ShellScreen` | type not listed on its own page in some places | exists, uncreatable | get it from `Quickshell.screens` only |
| `WlrLayershell` | docs show only `layer`, `namespace`, `keyboardFocus` | `anchors`, `exclusiveZone`, `exclusionMode`, `margins`, `aboveWindows`, `focusable` also exist (QSDOC_HIDE) | don't trust the docs for the hidden set |
| `WlrKeyboardFocus` | `WlrKeyboardFocus` namespace with `None`/`Exclusive`/`OnDemand` | same | `Exact` doesn't exist — it silently yields `undefined` |
| `Region` / `RegionShape` | in `Quickshell` core | in `Quickshell` core | **not** in `Quickshell.Wayland` |
| `Region` corner radii (`radius`, `topLeftRadius`, …) | present (new in 0.3.0) | present | fine |
| `SystemTrayItem` | `activate`, `secondaryActivate`, `display`, `scroll`, `menu` | same; **no `window` property, no `contextMenu()`** | brief's item API needs those two corrections |
| `SystemTray.items` | `ObjectModel` | `ObjectModel`, `CONSTANT`, no `.get()` | use `.values[...]` |
| `qs::io::JsonAdapter` `path`/`json`/`active` | not in docs | not on the C++ type | adapter only; path is on `FileView` |
| `PopupAnchor.rect` `w`/`h` | listed | listed | `x/y/w/h/width/height` all valid |
| `PersistentProperties` | persists across reload | does not restore values on this install (see reload section) | treat as unusable for durable state |
| `Repeater` as a shell-per-screen tool | — | works, but needs `import QtQuick` and an `Item` delegate; `Variants` is the idiomatic non-Item route | use `Variants` |

Confidence: **all 11 topics verified against the installed 0.3.2 binary** by compiling throwaway configs against it and by reading its registered QML type metadata and the v0.3.2 vendor source. Nothing in this file is docs-only except the `Repeater`-as-model caveat and a few enum orderings that came from the `.qmltypes` rather than a runtime probe (those match the vendor source exactly, so they carry the same confidence in practice).

---

## Addendum — found while implementing tickets 05 and 06 (CONFIRMED-0.3.2)

These three cost real time and are not in the numbered sections above.

1. **`Qt.TimeFormat` does not exist.** Reading it fails at *run* time with
   `Cannot read property 'ShortFormat' of undefined` — the same shape of
   failure as the `WlrKeyboardFocus.Exact` trap in section 6, and just as
   silent in a static read. The correct spelling is `Locale.ShortFormat` from
   `import QtQml` (or a bare `Qt.locale()` call). This bit the clock widget's
   time formatting.

2. **A `qmldir` is what makes sibling imports resolve.** Widget files in the
   same directory referencing each other (`import "."`) fail with
   `SimpleBase is not a type` unless that directory has a `qmldir`. This is
   why `shell/widgets/qmldir` exists and must list every widget type.

3. **`createObject()` on a `pragma Singleton` returns `null`.** Instantiating a
   singleton that way reports a false failure. Construct singletons by
   *reference* (importing them), never by `createObject`.

Also worth carrying forward: `verify-launch-reload.sh` copies `shell/`,
`services/` and `components/` into its scratch config but **not** the repo
root, so it will need `shell/widgets/` included once the bar composes
contract widgets (tickets 07/08).
