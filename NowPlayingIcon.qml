import QtQuick
import QtQuick.Shapes
import qs.Commons
import "MusicModel.js" as MusicModel

// A single sound-wave stroke, tapered to a point at both ends. While playing
// it travels; when stopped it settles into a flat line.
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

  implicitWidth: iconSize
  implicitHeight: iconSize

  Behavior on amplitude {
    NumberAnimation { duration: Style.duration(220); easing.type: Easing.OutCubic }
  }

  // The bar sizes an icon from what it paints. This fixed box keeps that
  // constant, or the icon would rescale as the wave changes height. It covers
  // exactly the most ink the wave can draw (its span plus the round caps), so
  // the wave fills the bar's icon size like the glyphs next to it.
  Rectangle {
    anchors.fill: parent
    anchors.margins: root.iconSize / 16
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
    }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: root.iconSize / 8
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: MusicModel.wavePath(root.iconSize, root.amplitude, root.phase) }
    }
  }
}
