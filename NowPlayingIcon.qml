import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import qs.Commons
import "MusicModel.js" as MusicModel

// A single sound-wave stroke. While playing it travels; when stopped it settles
// into a flat line. It is laid out on the screen's own pixel grid: the stroke
// is a whole number of pixels and the flat line covers whole rows, so it is as
// sharp as the font glyphs beside it in the bar.
Item {
  id: root

  property real iconSize: 16
  property color color: "white"
  // Motion only happens with `moving`; `raised` alone draws a still wave.
  property bool moving: false
  property bool raised: moving

  property real amplitude: raised ? 1 : 0
  property real phase: 0
  property double lastTick: 0

  // One device pixel in this item's coordinates. The window knows the real
  // fractional scale (1.25, say); Screen rounds it up to a whole number.
  readonly property real pixelRatio: Window.window && Window.window.devicePixelRatio > 0
    ? Window.window.devicePixelRatio
    : (Screen.devicePixelRatio > 0 ? Screen.devicePixelRatio : 1)
  readonly property real px: 1 / pixelRatio
  readonly property var grid: MusicModel.waveGrid(iconSize * pixelRatio)
  // How far the wave shifts so its own pixels line up with the screen's. The
  // bar can place this item at a fraction of a pixel, which would otherwise
  // blur the flat line across three rows.
  property real snapX: 0
  property real snapY: 0

  function snapToPixels() {
    if (!root.visible) return
    var scene = root.mapToItem(null, 0, 0)
    root.snapX = MusicModel.pixelSnap(scene.x, root.pixelRatio)
    root.snapY = MusicModel.pixelSnap(scene.y, root.pixelRatio)
  }

  function scheduleSnap() { Qt.callLater(root.snapToPixels) }

  // The icon's place on screen moves whenever anything above it moves, such
  // as the bar shifting it over when a neighbouring widget changes width. So
  // every ancestor is watched, and the wave snaps again on the next frame.
  // Qt.callLater folds a burst of moves into one snap.
  property var watchedAncestors: []

  function watchAncestors() {
    unwatchAncestors()
    var watched = []
    for (var item = root.parent; item; item = item.parent) {
      item.xChanged.connect(scheduleSnap)
      item.yChanged.connect(scheduleSnap)
      item.scaleChanged.connect(scheduleSnap)
      item.parentChanged.connect(watchAncestors)
      watched.push(item)
    }
    watchedAncestors = watched
    scheduleSnap()
  }

  function unwatchAncestors() {
    for (var i = 0; i < watchedAncestors.length; i++) {
      var item = watchedAncestors[i]
      if (!item) continue
      // An ancestor can be gone already when the bar is torn down.
      try {
        item.xChanged.disconnect(scheduleSnap)
        item.yChanged.disconnect(scheduleSnap)
        item.scaleChanged.disconnect(scheduleSnap)
        item.parentChanged.disconnect(watchAncestors)
      } catch (error) {}
    }
    watchedAncestors = []
  }

  Component.onCompleted: watchAncestors()
  Component.onDestruction: unwatchAncestors()
  onParentChanged: watchAncestors()
  onXChanged: scheduleSnap()
  onYChanged: scheduleSnap()
  onVisibleChanged: Qt.callLater(snapToPixels)
  onWidthChanged: Qt.callLater(snapToPixels)
  onHeightChanged: Qt.callLater(snapToPixels)
  onAmplitudeChanged: snapToPixels()
  onPixelRatioChanged: Qt.callLater(snapToPixels)

  implicitWidth: iconSize
  implicitHeight: iconSize

  Behavior on amplitude {
    NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic }
  }

  // The bar sizes an icon from what it paints. This fixed box keeps that
  // constant at exactly the icon size, so the wave is drawn at a scale of one
  // and stays on the pixel grid, and the icon never rescales as it moves.
  Rectangle {
    anchors.fill: parent
    color: "transparent"
  }

  Timer {
    interval: 100
    repeat: true
    running: root.moving
    onRunningChanged: root.lastTick = Date.now()
    onTriggered: {
      var now = Date.now()
      root.phase = MusicModel.advancePhase(root.phase, now - root.lastTick)
      root.lastTick = now
      root.snapToPixels()
    }
  }

  // The clip keeps the shifted wave inside the fixed box, so the bar never
  // measures it as bigger than the icon size and rescales it.
  Item {
    anchors.fill: parent
    clip: true

    Shape {
      x: root.snapX
      y: root.snapY
      width: parent.width
      height: parent.height
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.color
        strokeWidth: root.grid.stroke * root.px
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
        PathSvg { path: MusicModel.wavePath(root.grid, root.amplitude, root.phase, root.px) }
      }
    }
  }
}
