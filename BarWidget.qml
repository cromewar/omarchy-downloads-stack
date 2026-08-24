import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "FileKind.js" as FileKind

// A macOS-dock "Downloads stack" for the Omarchy bar: one icon that counts new
// arrivals, and a popup you can drag files straight out of into any other app.
//
// The drag is the reason this widget exists, and it shapes two decisions that
// would otherwise look odd:
//
//   * `close()` refuses while a drag is in flight. Starting a Wayland drag
//     takes the pointer grab away from the popup, which trips the popup's own
//     focus-grab dismissal — and destroying the source surface mid-drag makes
//     the compositor cancel the drag. Holding the popup open until the drop
//     lands is what makes the gesture survive.
//   * every tile's MouseArea sets `preventStealing`, so the scrolling body
//     never reinterprets the first few pixels of a drag-out as a flick.
BarWidget {
  id: root
  moduleName: "cromewar.downloads-stack"

  // ------------------------------------------------------------- settings
  readonly property string home: Quickshell.env("HOME")

  // Read from user-dirs.dirs rather than shelling out to `xdg-user-dir`, so a
  // localized or relocated Downloads folder still resolves with no subprocess.
  property string xdgDownload: ""

  readonly property string folderPath: {
    var configured = String(root.setting("folder", "")).replace(/^\s+|\s+$/g, "")
    var chosen = configured !== "" ? configured
      : (root.xdgDownload !== "" ? root.xdgDownload : root.home + "/Downloads")
    chosen = chosen.replace(/^~(?=\/|$)/, root.home)
    return chosen.length > 1 ? chosen.replace(/\/+$/, "") : chosen
  }
  readonly property string folderName: {
    var i = root.folderPath.lastIndexOf("/")
    return i >= 0 ? root.folderPath.substring(i + 1) : root.folderPath
  }

  readonly property int maxItems: {
    var v = Math.round(Number(root.setting("maxItems", 12)))
    return isFinite(v) && v > 0 ? Math.min(v, 60) : 12
  }
  readonly property bool showHidden: root.setting("showHidden", false) === true
  readonly property string badgeMode: String(root.setting("badge", "new"))
  readonly property bool closeAfterDrag: root.setting("closeAfterDrag", true) !== false
  readonly property string fileManager: String(root.setting("fileManager", "nautilus"))

  // Session-local: flipping the view from the popup header should be instant,
  // and a widget cannot write back to shell.json. The setting seeds it, and the
  // setting is still what persists across a restart.
  property string view: String(root.setting("view", "grid")) === "list" ? "list" : "grid"
  readonly property bool isGrid: root.view === "grid"

  // ---------------------------------------------------------------- state
  property var files: []        // newest first, already filtered and capped
  property int totalCount: 0    // eligible files in the folder, before the cap
  property bool popupOpen: false
  property bool dragging: false
  property real lastSeenMs: 0   // marker persisted across shell restarts
  property real highlightMs: 0  // frozen at open, so the popup can still mark
                                // what is new after the count has been cleared
  property real nowMs: 0

  readonly property int extraCount: Math.max(0, root.totalCount - root.files.length)
  readonly property var newest: root.files.length > 0 ? root.files[0] : null

  function modifiedMs(entry) {
    if (!entry) return 0
    var m = entry.modified
    var t = (m instanceof Date) ? m.getTime() : Number(m)
    return isFinite(t) ? t : 0
  }

  readonly property int newCount: {
    if (root.lastSeenMs <= 0) return 0
    var n = 0
    for (var i = 0; i < root.files.length; i++)
      if (root.modifiedMs(root.files[i]) > root.lastSeenMs) n++
    return n
  }

  readonly property string badgeText: {
    if (root.badgeMode === "none") return ""
    var n = root.badgeMode === "count" ? root.totalCount : root.newCount
    if (n <= 0) return ""
    return n > 99 ? "99+" : String(n)
  }

  // --------------------------------------------------------------- actions
  function run(args) { Quickshell.execDetached(args) }

  function openFile(url) {
    root.run(["xdg-open", "" + url])
    root.popupOpen = false
  }

  function openFolder() {
    root.run(["xdg-open", root.folderPath])
    root.popupOpen = false
  }

  // Nautilus is Omarchy's Files app and the only one here that reliably takes a
  // "highlight this one" argument; anything else just gets the folder.
  function reveal(path) {
    if (root.fileManager === "nautilus") {
      root.run(["nautilus", "--select", "" + path])
      root.popupOpen = false
    } else {
      root.openFolder()
    }
  }

  function copyPath(path) { root.run(["wl-copy", "--", "" + path]) }

  function markSeen() {
    var now = Date.now()
    root.lastSeenMs = now
    seenFile.setText(String(now))
  }

  function openStack() {
    root.highlightMs = root.lastSeenMs
    root.nowMs = Date.now()
    root.popupOpen = true
    root.markSeen()
  }

  // open/close/opened is the shape Bar.findPanelWidget looks for, so
  // `omarchy-shell shell toggle cromewar.downloads-stack '{}'` and a keybinding
  // can both reach the stack without the mouse.
  readonly property bool opened: root.popupOpen
  function open() { root.openStack() }
  function close() {
    // See the note at the top: dropping the surface mid-drag kills the drag.
    if (root.dragging) return
    root.popupOpen = false
  }

  function onDragFinished() {
    root.dragging = false
    if (root.closeAfterDrag) root.popupOpen = false
  }

  // ------------------------------------------------------------------ data
  FileView {
    id: userDirs
    path: root.home + "/.config/user-dirs.dirs"
    preload: true
    printErrors: false
    onLoaded: {
      var m = /^\s*XDG_DOWNLOAD_DIR\s*=\s*"?([^"\n]*)"?\s*$/m.exec(text() || "")
      root.xdgDownload = m ? m[1].replace(/\$HOME/g, root.home) : ""
    }
    onLoadFailed: root.xdgDownload = ""
  }

  FileView {
    id: seenFile
    path: Color.stateHome + "/omarchy/downloads-stack-seen"
    preload: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.lastSeenMs = Number((text() || "").replace(/\s+/g, "")) || 0
    // No marker yet: stamp now rather than counting every file already sitting
    // in Downloads as "new" the first time the widget loads.
    onLoadFailed: root.markSeen()
  }

  FolderListModel {
    id: folderModel
    // encodeURI so spaces and accents in the path survive the round trip into a
    // URL; the model hands those same encoded URLs back for the drag payload.
    folder: "file://" + encodeURI(root.folderPath)
    showDirs: true
    showFiles: true
    showDotAndDotDot: false
    showHidden: root.showHidden
    // QDir::Time is newest-first already, so this is deliberately not reversed.
    sortField: FolderListModel.Time
    sortReversed: false
    onCountChanged: settle.restart()
    onStatusChanged: if (status === FolderListModel.Ready) settle.restart()
  }

  // A browser writing a large file touches the folder repeatedly; rebuilding on
  // every notification would rebuild the list dozens of times per download.
  Timer {
    id: settle
    interval: 80
    onTriggered: root.rebuild()
  }

  function rebuild() {
    var out = []
    var eligible = 0
    var count = folderModel.count
    for (var i = 0; i < count; i++) {
      var name = "" + folderModel.get(i, "fileName")
      if (FileKind.isPartial(name)) continue
      eligible++
      if (out.length >= root.maxItems) continue
      out.push({
        url: "" + folderModel.get(i, "fileUrl"),
        path: "" + folderModel.get(i, "filePath"),
        name: name,
        isDir: folderModel.get(i, "fileIsDir") === true,
        size: folderModel.get(i, "fileSize"),
        modified: folderModel.get(i, "fileModified")
      })
    }
    root.files = out
    root.totalCount = eligible
  }

  onMaxItemsChanged: root.rebuild()
  onShowHiddenChanged: root.rebuild()

  // Only ticks while the stack is on screen — the relative timestamps are the
  // only thing that goes stale, and nothing reads them when it is closed.
  Timer {
    running: root.popupOpen
    interval: 30000
    repeat: true
    triggeredOnStart: true
    onTriggered: root.nowMs = Date.now()
  }

  // ------------------------------------------------------------------ face
  implicitWidth: face.implicitWidth
  implicitHeight: face.implicitHeight

  WidgetButton {
    id: face
    anchors.fill: parent
    bar: root.bar
    // The count rides beside the glyph instead of on top of it. A macOS-style
    // corner badge needs more room than a 30px text bar has: at that size any
    // pill big enough to hold a digit covers most of a 16px icon. Alongside, it
    // stays legible at every bar height and font scale — and on a vertical bar,
    // where there is no width to spare, the tint alone carries the signal.
    text: root.badgeText !== "" && !root.vertical
      ? "󰉍 " + root.badgeText
      : "󰉍"
    fontSize: Style.font.icon
    horizontalMargin: 7
    // Tinted while something is new, so the widget still reads as "look here"
    // out of the corner of your eye, which is what a badge was for.
    active: root.popupOpen || (root.badgeMode !== "none" && root.newCount > 0)
    tooltipText: {
      if (root.popupOpen) return ""
      if (!root.newest) return "No files in " + root.folderName
      return root.newest.name + "   ·   " + root.totalCount
        + (root.totalCount === 1 ? " file" : " files")
        + (root.newCount > 0 ? "   ·   " + root.newCount + " new" : "")
    }

    onPressed: function(button) {
      if (button === Qt.RightButton) root.openFolder()
      else if (button === Qt.MiddleButton) root.markSeen()
      else if (root.popupOpen) root.popupOpen = false
      else root.openStack()
    }
  }

  // ----------------------------------------------------------------- popup
  readonly property int tileSize: Style.space(58)
  readonly property int tileWidth: Style.space(80)
  readonly property int tileHeight: Style.space(104)
  readonly property int maxBodyHeight: Style.space(400)

  PopupCard {
    id: popup
    anchorItem: face
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(root.isGrid ? 356 : 396))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      width: parent.width
      spacing: Style.spacing.md

      // ---- header
      Item {
        width: parent.width
        implicitHeight: Math.max(headerText.implicitHeight, headerActions.implicitHeight)

        Text {
          id: headerText
          anchors.left: parent.left
          anchors.right: headerActions.left
          anchors.rightMargin: Style.spacing.controlGap
          anchors.verticalCenter: parent.verticalCenter
          text: root.folderName + (root.totalCount > 0 ? "  ·  " + root.totalCount : "")
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }

        Row {
          id: headerActions
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.controlGap

          PanelActionButton {
            iconText: root.isGrid ? "󰉹" : "󰕰"
            tooltipText: root.isGrid ? "Show as a list" : "Show as a grid"
            foreground: root.bar ? root.bar.foreground : Color.foreground
            bordered: true
            onClicked: root.view = root.isGrid ? "list" : "grid"
          }

          PanelActionButton {
            iconText: "󰝰"
            tooltipText: "Open " + root.folderPath
            foreground: root.bar ? root.bar.foreground : Color.foreground
            bordered: true
            onClicked: root.openFolder()
          }
        }
      }

      // ---- empty state
      Text {
        width: parent.width
        visible: root.files.length === 0
        height: visible ? implicitHeight + Style.spacing.xl : 0
        text: "Nothing in " + root.folderName + " yet"
        color: Color.muted
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
      }

      // ---- files
      Flickable {
        id: body
        visible: root.files.length > 0
        width: parent.width
        height: visible ? Math.min(bodyContent.implicitHeight, root.maxBodyHeight) : 0
        contentWidth: width
        contentHeight: bodyContent.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Item {
          id: bodyContent
          width: body.width
          implicitHeight: root.isGrid ? gridView.implicitHeight : listView.implicitHeight

          // ---- grid
          Grid {
            id: gridView
            visible: root.isGrid
            width: parent.width
            columns: Math.max(1, Math.floor(width / root.tileWidth))
            spacing: 0

            Repeater {
              model: root.isGrid ? root.files : []

              FileDragItem {
                id: tile
                required property var modelData

                width: gridView.width / gridView.columns
                height: root.tileHeight
                fileUrl: modelData.url
                fileName: modelData.name
                isDir: modelData.isDir
                // Only the icon becomes the cursor pixmap: grabbing the whole
                // tile makes it look like you picked up a row of a list rather
                // than the file itself.
                grabTarget: tileThumb

                onClicked: root.openFile(modelData.url)
                onRightClicked: root.reveal(modelData.path)
                onMiddleClicked: root.copyPath(modelData.path)
                onDragStarted: root.dragging = true
                onDragEnded: root.onDragFinished()

                BorderSurface {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.xxs
                  radius: Style.cornerRadius
                  color: tile.hovered
                    ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
                    : "transparent"
                  borderSpec: Border.none()
                  Behavior on color { ColorAnimation { duration: 60 } }
                }

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.sm
                  spacing: Style.spacing.xs

                  Item {
                    width: parent.width
                    height: root.tileSize

                    FileThumb {
                      id: tileThumb
                      anchors.centerIn: parent
                      width: root.tileSize
                      height: root.tileSize
                      fileName: tile.fileName
                      fileUrl: tile.fileUrl
                      isDir: tile.isDir
                      foreground: root.bar ? root.bar.foreground : Color.foreground
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      scale: tile.hovered ? 1.08 : 1.0
                      Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
                    }

                    Rectangle {
                      visible: root.highlightMs > 0 && root.modifiedMs(tile.modelData) > root.highlightMs
                      anchors.right: tileThumb.right
                      anchors.top: tileThumb.top
                      width: Style.space(7)
                      height: width
                      radius: width / 2
                      color: root.bar ? root.bar.urgent : Color.urgent
                    }
                  }

                  Text {
                    width: parent.width
                    text: FileKind.shortName(tile.fileName, 20)
                    color: tile.hovered
                      ? (root.bar ? root.bar.foreground : Color.foreground)
                      : Color.muted
                    horizontalAlignment: Text.AlignHCenter
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    // Qt elides wrapped text only at the end, so ElideMiddle here
                    // collapses the label to one line. shortName() already put the
                    // useful tail back; this is just the backstop.
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WrapAnywhere
                  }
                }
              }
            }
          }

          // ---- list
          Column {
            id: listView
            visible: !root.isGrid
            width: parent.width
            spacing: 0

            Repeater {
              model: root.isGrid ? [] : root.files

              FileDragItem {
                id: row
                required property var modelData

                width: listView.width
                height: Math.max(Style.spacing.popupRowHeight, Style.space(38))
                fileUrl: modelData.url
                fileName: modelData.name
                isDir: modelData.isDir
                grabTarget: rowIconBox

                onClicked: root.openFile(modelData.url)
                onRightClicked: root.reveal(modelData.path)
                onMiddleClicked: root.copyPath(modelData.path)
                onDragStarted: root.dragging = true
                onDragEnded: root.onDragFinished()

                BorderSurface {
                  anchors.fill: parent
                  anchors.margins: Style.spacing.hairline
                  radius: Style.cornerRadius
                  color: row.hovered
                    ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
                    : "transparent"
                  borderSpec: Border.none()
                  Behavior on color { ColorAnimation { duration: 60 } }
                }

                Item {
                  id: rowIconBox
                  anchors.left: parent.left
                  anchors.leftMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(26)
                  height: Style.space(26)

                  FileThumb {
                    anchors.fill: parent
                    fileName: row.fileName
                    fileUrl: row.fileUrl
                    isDir: row.isDir
                    foreground: root.bar ? root.bar.foreground : Color.foreground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                  }
                }

                Rectangle {
                  visible: root.highlightMs > 0 && root.modifiedMs(row.modelData) > root.highlightMs
                  anchors.right: rowIconBox.right
                  anchors.top: rowIconBox.top
                  width: Style.space(7)
                  height: width
                  radius: width / 2
                  color: root.bar ? root.bar.urgent : Color.urgent
                }

                Text {
                  id: rowMeta
                  anchors.right: parent.right
                  anchors.rightMargin: Style.spacing.sm
                  anchors.verticalCenter: parent.verticalCenter
                  text: FileKind.formatAge(row.modelData.modified, root.nowMs)
                  color: Color.muted
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
                }

                Column {
                  anchors.left: rowIconBox.right
                  anchors.leftMargin: Style.spacing.controlGap
                  anchors.right: rowMeta.left
                  anchors.rightMargin: Style.spacing.controlGap
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 0

                  Text {
                    width: parent.width
                    text: FileKind.shortName(row.fileName, 52)
                    color: root.bar ? root.bar.foreground : Color.foreground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideMiddle
                  }

                  Text {
                    width: parent.width
                    text: FileKind.kindOf(row.fileName, row.isDir)
                      + (row.isDir ? "" : "  ·  " + FileKind.formatSize(row.modelData.size))
                    color: Color.muted
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }
      }

      // ---- footer: the plain "just show me the folder" escape hatch
      BorderSurface {
        id: footer
        width: parent.width
        implicitHeight: Style.spacing.popupRowHeight
        radius: Style.cornerRadius
        color: footerMouse.containsMouse
          ? Style.hoverFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
          : Style.normalFillFor(root.bar ? root.bar.foreground : Color.foreground, Color.accent)
        borderSpec: Border.none()
        Behavior on color { ColorAnimation { duration: 60 } }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlGap
          anchors.verticalCenter: parent.verticalCenter
          text: "󰝰  Open " + root.folderName
          color: root.bar ? root.bar.foreground : Color.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlGap
          anchors.verticalCenter: parent.verticalCenter
          visible: root.extraCount > 0
          text: "+" + root.extraCount + " more"
          color: Color.muted
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        MouseArea {
          id: footerMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openFolder()
        }
      }
    }
  }
}
