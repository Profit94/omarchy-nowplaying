import QtQuick
import QtQuick.Shapes
import qs.Commons
import "MusicModel.js" as MusicModel

// Two of the bar icon's waves wrapped into rings that ripple against each
// other. The live output level sets how far they ripple; while music plays the
// front ring travels one way and the softer back ring the other. Paused, both
// settle into one still, dim circle, the way the bar icon settles into a line.
Item {
  id: root

  property real level: 0
  property bool playing: false
  property bool moving: false
  property color color: "white"
  property color dimColor: "grey"

  readonly property real radius: Style.spaceReal(18)
  readonly property real reachRest: Style.spaceReal(0.8)
  readonly property real reachLoud: Style.spaceReal(3.2)
  readonly property real lineWidth: Style.spaceReal(1.1)
  readonly property color ink: playing ? color : dimColor

  // Eased, so the rings swell and settle instead of jumping between readings.
  property real reach: playing ? reachRest + reachLoud * MusicModel.clampFraction(level) : 0
  Behavior on reach {
    NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
  }

  property real phase: 0
  NumberAnimation on phase {
    from: 0
    to: 2 * Math.PI
    duration: MusicModel.WAVE_PERIOD_MS
    loops: Animation.Infinite
    running: root.moving
    paused: running && !root.playing
  }

  implicitWidth: Style.space(48)
  implicitHeight: Style.space(48)

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // Back ring: more peaks, a smaller swing, half strength, turning the other
    // way. Its phase runs at a whole multiple, so the loop has no seam.
    ShapePath {
      fillColor: "transparent"
      strokeColor: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.5)
      strokeWidth: root.lineWidth
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: MusicModel.ringPath(root.width / 2, root.height / 2, root.radius, root.reach * 0.8, -2 * root.phase, 9) }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.ink
      strokeWidth: root.lineWidth
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: MusicModel.ringPath(root.width / 2, root.height / 2, root.radius, root.reach, root.phase, 6) }
    }
  }
}
