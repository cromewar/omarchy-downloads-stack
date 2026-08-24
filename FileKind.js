.pragma library

// Everything the stack needs to know about a file from its name alone: no
// stat, no mime lookup, no icon theme. Keeping it name-based means a tile can
// be drawn the instant the folder model lists it, before anything is read off
// disk — which is what makes a download appear in the bar the moment it lands.

function extOf(name) {
  if (!name) return ""
  var i = ("" + name).lastIndexOf(".")
  return i > 0 ? ("" + name).substring(i + 1).toLowerCase() : ""
}

var IMAGE_EXT = ["png", "jpg", "jpeg", "gif", "bmp", "webp", "tif", "tiff", "ico", "avif"]

// Deliberately excludes svg/jxl: QtQuick can decode them only with extra image
// plugins, and a broken Image is worse than a glyph.
function isImage(name) {
  return IMAGE_EXT.indexOf(extOf(name)) !== -1
}

// Downloads in flight. A browser writes these until the transfer completes and
// then renames, so showing them means showing a file that cannot be dragged.
var PARTIAL_EXT = ["part", "crdownload", "download", "opdownload", "partial", "tmp", "!ut", "aria2"]

function isPartial(name) {
  if (!name) return true
  var n = "" + name
  if (n.charAt(0) === "~") return true
  return PARTIAL_EXT.indexOf(extOf(n)) !== -1
}

function kindOf(name, isDir) {
  if (isDir) return "Folder"
  var e = extOf(name)
  if (!e) return "File"
  if (isImage(name)) return e.toUpperCase() + " image"
  switch (e) {
  case "pdf": return "PDF document"
  case "doc": case "docx": case "odt": case "rtf": return "Document"
  case "xls": case "xlsx": case "ods": case "csv": case "tsv": return "Spreadsheet"
  case "ppt": case "pptx": case "odp": return "Presentation"
  case "txt": case "md": case "log": return "Text"
  case "zip": case "tar": case "gz": case "tgz": case "bz2": case "xz":
  case "7z": case "rar": case "zst": return "Archive"
  case "mp3": case "flac": case "wav": case "ogg": case "m4a": case "aac":
  case "opus": return "Audio"
  case "mp4": case "mkv": case "webm": case "avi": case "mov": case "wmv":
    return "Video"
  case "appimage": case "run": case "bin": case "exe": case "msi": case "sh":
    return "Application"
  case "deb": case "rpm": case "pkg": case "apk": case "zst.pkg": return "Package"
  case "iso": case "img": case "dmg": return "Disk image"
  case "torrent": return "Torrent"
  case "svg": case "jxl": return e.toUpperCase() + " image"
  }
  return e.toUpperCase() + " file"
}

// Material Design glyphs from the Nerd Font the bar already renders in, so the
// stack inherits the theme's font and colour instead of dragging in an icon set.
function glyphOf(name, isDir) {
  if (isDir) return "󰉋"
  var e = extOf(name)
  if (isImage(name) || e === "svg" || e === "jxl") return "󰈟"
  switch (e) {
  case "pdf": return "󰈦"
  case "doc": case "docx": case "odt": case "rtf": return "󰈙"
  case "xls": case "xlsx": case "ods": case "csv": case "tsv": return "󰈛"
  case "ppt": case "pptx": case "odp": return "󰈧"
  case "txt": case "md": case "log": return "󰈙"
  case "zip": case "tar": case "gz": case "tgz": case "bz2": case "xz":
  case "7z": case "rar": case "zst": return "󰗄"
  case "mp3": case "flac": case "wav": case "ogg": case "m4a": case "aac":
  case "opus": return "󰈣"
  case "mp4": case "mkv": case "webm": case "avi": case "mov": case "wmv":
    return "󰈫"
  case "appimage": case "run": case "bin": case "exe": case "msi": case "sh":
    return "󰆍"
  case "deb": case "rpm": case "pkg": case "apk": return "󰏖"
  case "iso": case "img": case "dmg": return "󰗮"
  case "html": case "htm": case "css": case "js": case "ts": case "json":
  case "xml": case "yaml": case "yml": case "toml": case "py": case "rb":
  case "go": case "rs": case "c": case "h": case "cpp": case "java": case "qml":
    return "󰈮"
  }
  return "󰈔"
}

// Middle-truncate so the tail — which is where the extension and the part that
// distinguishes "report-2024-final.pdf" from "report-2024-draft.pdf" live —
// survives. Text.ElideMiddle cannot do this: Qt only elides multi-line text at
// the end, and a grid label needs both wrapping and a readable tail.
function shortName(name, budget) {
  var n = "" + (name || "")
  if (n.length <= budget) return n
  var head = Math.max(3, Math.round((budget - 1) * 0.55))
  var tail = Math.max(3, budget - 1 - head)
  return n.substring(0, head) + "\u2026" + n.substring(n.length - tail)
}

function formatSize(bytes) {
  var b = Number(bytes)
  if (!isFinite(b) || b < 0) return ""
  if (b < 1024) return b + " B"
  var units = ["KB", "MB", "GB", "TB"]
  var v = b / 1024
  for (var i = 0; i < units.length; i++) {
    if (v < 1024 || i === units.length - 1)
      return (v < 10 ? v.toFixed(1) : Math.round(v)) + " " + units[i]
    v /= 1024
  }
  return ""
}

// Coarse on purpose: the stack is about "what just landed", so minutes matter
// near now and nothing below a day matters after that.
function formatAge(modified, nowMs) {
  if (!modified) return ""
  var t = modified instanceof Date ? modified.getTime() : Number(modified)
  if (!isFinite(t)) return ""
  var secs = Math.max(0, Math.round((nowMs - t) / 1000))
  if (secs < 60) return "just now"
  var mins = Math.round(secs / 60)
  if (mins < 60) return mins + "m ago"
  var hours = Math.round(mins / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.round(hours / 24)
  if (days < 7) return days + "d ago"
  return Math.round(days / 7) + "w ago"
}
