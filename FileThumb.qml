import QtQuick
import qs.Commons
import "FileKind.js" as FileKind

// Real thumbnail for images, a font glyph for everything else. The glyph path
// costs nothing and inherits the theme's colour and font, so the stack still
// looks like the rest of the bar on a machine with no icon theme installed.
Item {
  id: root

  property string fileName: ""
  property url fileUrl
  property bool isDir: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real glyphSize: Math.round(Math.min(width, height) * 0.74)

  readonly property bool wantsThumb: !isDir && FileKind.isImage(fileName)
  readonly property bool thumbReady: wantsThumb && thumb.status === Image.Ready

  Text {
    anchors.centerIn: parent
    visible: !root.thumbReady
    text: FileKind.glyphOf(root.fileName, root.isDir)
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: root.glyphSize
    renderType: Text.NativeRendering
  }

  Image {
    id: thumb
    anchors.fill: parent
    visible: root.thumbReady
    source: root.wantsThumb ? root.fileUrl : ""
    asynchronous: true
    fillMode: Image.PreserveAspectCrop
    // A 12MP screenshot decoded at full size to be drawn 64px wide costs more
    // memory than the rest of the bar put together; cap it at what is shown.
    sourceSize.width: Math.max(2, Math.round(width * 2))
    sourceSize.height: Math.max(2, Math.round(height * 2))
    smooth: true
    mipmap: true
    clip: true
  }
}
