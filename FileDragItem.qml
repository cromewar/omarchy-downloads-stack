import QtQuick

// Makes whatever is put inside it draggable out of the shell and into any other
// application. This is the whole point of the stack, and it is the one thing a
// bar popup is not obviously allowed to do: the drag below is a real
// `wl_data_device` drag started from the popup's own Wayland surface, so the
// file lands in whichever app the pointer is over when the button comes up —
// browser upload field, editor, chat window, file manager.
Item {
  id: root

  property url fileUrl
  property string fileName: ""
  property bool isDir: false

  // The item rendered as the pixmap under the cursor. Defaults to everything.
  property Item grabTarget: root

  property bool dragging: false

  signal clicked()
  signal rightClicked()
  signal middleClicked()
  signal dragStarted()
  signal dragEnded()

  readonly property bool hovered: mouse.containsMouse
  readonly property bool held: mouse.pressed && !dragging

  default property alias content: holder.data
  Item { id: holder; anchors.fill: parent }

  Drag.dragType: Drag.Automatic
  Drag.active: false
  // No MoveAction on purpose. A file manager offered one would happily take the
  // file *out* of Downloads, and this gesture means "put a copy over there".
  Drag.supportedActions: Qt.CopyAction | Qt.LinkAction
  Drag.proposedAction: Qt.CopyAction
  Drag.mimeData: ({
    "text/uri-list": ("" + root.fileUrl + "\r\n"),
    "text/plain": ("" + root.fileUrl)
  })
  Drag.onDragFinished: {
    root.dragging = false
    root.dragEnded()
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    // The stack body scrolls. Without this, a Flickable reinterprets the first
    // few pixels of a drag-out as a flick and the drag never starts.
    preventStealing: true

    property point pressPos

    onPressed: (m) => { pressPos = Qt.point(m.x, m.y) }

    onPositionChanged: (m) => {
      if (root.dragging || !(pressedButtons & Qt.LeftButton)) return
      var dx = m.x - pressPos.x
      var dy = m.y - pressPos.y
      if (dx * dx + dy * dy < 64) return   // ~8px, Qt's own start-drag distance
      root.dragging = true
      root.dragStarted()
      // grabToImage is asynchronous, so the drag starts a frame late. Invisible
      // at an 8px threshold, and it buys a real preview of the file under the
      // cursor instead of a blank rectangle.
      root.grabTarget.grabToImage(function (result) {
        if (!root.dragging) return
        root.Drag.imageSource = result.url
        root.Drag.active = true
      })
    }

    // A click is a release that never became a drag, so the two gestures never
    // fire together: dragging a file out does not also open it.
    onReleased: (m) => {
      if (root.dragging) return
      if (m.button === Qt.RightButton) root.rightClicked()
      else if (m.button === Qt.MiddleButton) root.middleClicked()
      else root.clicked()
    }
  }
}
