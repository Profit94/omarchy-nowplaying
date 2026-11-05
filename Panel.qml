import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "MusicModel.js" as MusicModel

Panel {
  id: root
  moduleName: "softwave.nowplaying"
  ipcTarget: "softwave.nowplaying"

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  // The system font. `omarchy font set` changes it for the whole shell.
  readonly property string fontFamily: Style.font.family
  readonly property int glowReach: Math.max(1, Style.spacing.popupPadding - Style.space(1))

  // ------------------------------------------------------------- the player

  readonly property var extraPlayers: MusicModel.parseExtraPlayers(setting("extraPlayers", ""))
  readonly property var allPlayers: Mpris.players ? Mpris.players.values : []
  readonly property var musicPlayers: MusicModel.musicPlayers(allPlayers, extraPlayers)
  property string preferredKey: ""
  // Set by the switcher, and let go when the panel closes.
  property string pinnedKey: ""
  readonly property var player: MusicModel.selectActive(musicPlayers, preferredKey, pinnedKey)

  readonly property bool isPlaying: !!player && !!player.isPlaying
  readonly property bool wantsIcon: !!player && (isPlaying || opened || setting("showWhenPaused", true) === true)

  // Players clear their metadata for a moment between tracks. Hiding is held
  // back so the icon doesn't blink and the bar doesn't shift each time.
  property bool iconShown: wantsIcon
  onWantsIconChanged: {
    if (wantsIcon) {
      hideDelay.stop()
      iconShown = true
    } else {
      hideDelay.restart()
    }
  }
  Timer {
    id: hideDelay
    interval: 1200
    onTriggered: {
      root.iconShown = false
      root.close()
    }
  }

  visible: iconShown
  implicitWidth: iconShown ? button.implicitWidth : 0
  implicitHeight: button.implicitHeight

  // ---------------------------------------------------------------- actions

  function adopt() {
    var key = MusicModel.playerKey(player)
    if (key) preferredKey = key
  }

  function playPause() {
    if (!player) return
    adopt()
    if (player.canTogglePlaying) player.togglePlaying()
    else if (player.isPlaying && player.canPause) player.pause()
    else if (!player.isPlaying && player.canPlay) player.play()
  }

  function skip(direction) {
    if (!player) return
    adopt()
    if (direction > 0 && player.canGoNext) {
      swapDirection = direction
      player.next()
    } else if (direction < 0 && player.canGoPrevious) {
      swapDirection = direction
      player.previous()
    }
  }

  function seekTo(fraction) {
    if (canSeek) player.position = MusicModel.clampFraction(fraction) * player.length
  }

  // --------------------------------------------------------------- progress

  // MPRIS doesn't announce position as it advances. Quickshell re-reads it when
  // positionChanged() fires, so this ticks only while the panel can show it.
  readonly property real position: player && player.positionSupported ? player.position : 0
  readonly property real length: player && player.lengthSupported ? player.length : 0
  readonly property bool canSeek: !!player && !!player.canSeek && !!player.positionSupported && length > 0
  readonly property real progress: length > 0 ? MusicModel.clampFraction(position / length) : 0

  Timer {
    interval: 500
    repeat: true
    running: root.opened && root.isPlaying
    onTriggered: root.player.positionChanged()
  }
  onOpenedChanged: {
    if (!opened) {
      if (pinnedKey) {
        preferredKey = pinnedKey
        pinnedKey = ""
      }
      return
    }
    if (player) player.positionChanged()
    syncArt()
  }

  // ------------------------------------------------------------ track change

  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string source: player ? (player.identity || player.desktopEntry || "") : ""
  readonly property string rawArtUrl: player ? MusicModel.safeArtUrl(player.trackArtUrl) : ""
  readonly property string trackKey: title + "\u0001" + artist + "\u0001" + MusicModel.playerKey(player)

  property string shownTitle: title
  property string shownArtist: artist
  property string shownSource: source
  property int swapDirection: 1
  property real infoOpacity: 1
  property real infoShift: 0
  property real iconOpacity: 1

  function applyTrack() {
    shownTitle = title
    shownArtist = artist
    shownSource = source
  }

  onSourceChanged: shownSource = source
  onTrackKeyChanged: {
    // Keep the outgoing track on show through a brief metadata gap.
    if (!title && !artist) return
    if (opened) {
      swapAnimation.restart()
    } else {
      applyTrack()
      swapDirection = 1
    }
    iconFlash.restart()
    if (player) player.positionChanged()
  }

  // Out the way the track is leaving, in from the other side.
  SequentialAnimation {
    id: swapAnimation
    ParallelAnimation {
      NumberAnimation { target: root; property: "infoOpacity"; to: 0; duration: Style.duration(100); easing.type: Easing.OutCubic }
      NumberAnimation { target: root; property: "infoShift"; to: -root.swapDirection * Style.space(10); duration: Style.duration(100); easing.type: Easing.OutCubic }
    }
    ScriptAction {
      script: {
        root.applyTrack()
        root.infoShift = root.swapDirection * Style.space(12)
      }
    }
    ParallelAnimation {
      NumberAnimation { target: root; property: "infoOpacity"; to: 1; duration: Style.duration(200); easing.type: Easing.OutCubic }
      NumberAnimation { target: root; property: "infoShift"; to: 0; duration: Style.duration(200); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    onFinished: root.swapDirection = 1
  }

  NumberAnimation {
    id: iconFlash
    target: root
    property: "iconOpacity"
    from: 0.35
    to: 1
    duration: Style.duration(260)
    easing.type: Easing.OutCubic
  }

  // --------------------------------------------------------------- artwork

  // Covers are downloaded by curl rather than by the Image element. Letting Qt
  // fetch them over HTTPS crashed the whole shell inside OpenSSL, when the TLS
  // setup on the image thread met the first use of the glow's shader. Fetches
  // only happen with the panel open, into a per-user runtime folder.
  property url artUrl: ""
  property string artSource: ""
  property string artFile: ""
  property string artDownloading: ""
  readonly property string artRoot: Quickshell.env("XDG_RUNTIME_DIR") + "/omarchy-nowplaying"
  readonly property string artFolder: artRoot + "/" + Date.now().toString(36)

  // Each shell start gets its own folder. A crash can leave one behind, so old
  // ones are cleared on the way up.
  Component.onCompleted: Quickshell.execDetached(["find", artRoot, "-mindepth", "1", "-maxdepth", "1",
    "-type", "d", "-mmin", "+60", "-exec", "rm", "-rf", "--", "{}", "+"])
  Component.onDestruction: Quickshell.execDetached(["rm", "-rf", "--", artFolder])

  function syncArt() {
    if (!opened || rawArtUrl === artSource) return
    artSource = rawArtUrl
    if (MusicModel.isRemoteArt(artSource)) {
      startArtDownload()
    } else {
      artDownload.running = false
      clearArtFile()
      artUrl = artSource
    }
  }

  function startArtDownload() {
    // A download in progress reports its exit first, which starts this one.
    if (artDownload.running) {
      artDownload.running = false
      return
    }
    artDownloading = artSource
    var target = artFolder + "/" + MusicModel.artFileName(artSource)
    artDownload.target = target
    artDownload.command = ["curl", "--silent", "--fail", "--location", "--max-redirs", "3",
      "--proto", "=https,http", "--max-time", "10", "--max-filesize", "10485760",
      "--create-dirs", "--output", target, "--url", artSource]
    artDownload.running = true
  }

  function clearArtFile() {
    if (artFile) Quickshell.execDetached(["rm", "-f", "--", artFile])
    artFile = ""
  }

  Process {
    id: artDownload
    property string target: ""
    onExited: function(exitCode) {
      if (root.artDownloading !== root.artSource) {
        if (MusicModel.isRemoteArt(root.artSource)) root.startArtDownload()
        return
      }
      if (exitCode === 0) {
        if (root.artFile !== target) root.clearArtFile()
        root.artFile = target
        root.artUrl = "file://" + target
      } else {
        root.artUrl = ""
      }
    }
  }

  onRawArtUrlChanged: syncArt()

  // ------------------------------------------------------------- audio level

  // Runs only while the panel is open and music is playing, so there is no
  // capture stream the rest of the time. It measures the output's real level.
  readonly property bool meterActive: opened && isPlaying && !Style.reduceMotion
  readonly property int barCount: 5
  property var levels: [0, 0, 0, 0, 0]
  property real meterCeiling: 0

  PwNodePeakMonitor {
    id: peakMonitor
    node: Pipewire.defaultAudioSink
    enabled: root.meterActive
  }

  // The newest reading enters at the left and moves right, so the bars show
  // the last moments of the real signal instead of an imitation spectrum.
  Timer {
    interval: 90
    repeat: true
    running: root.meterActive
    onTriggered: {
      var next = root.levels.slice(0, root.barCount - 1)
      root.meterCeiling = MusicModel.nextCeiling(peakMonitor.peak, root.meterCeiling)
      next.unshift(MusicModel.barLevel(peakMonitor.peak, root.meterCeiling))
      root.levels = next
    }
  }
  onMeterActiveChanged: {
    if (meterActive) return
    levels = [0, 0, 0, 0, 0]
    meterCeiling = 0
  }

  // -------------------------------------------------------------- bar button

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    visible: root.iconShown
    iconComponent: Component {
      Item {
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        opacity: root.iconOpacity

        NowPlayingIcon {
          anchors.fill: parent
          iconSize: parent.width
          moving: root.isPlaying && root.iconShown && !Style.reduceMotion
          raised: root.isPlaying
          color: root.isPlaying ? root.barForeground : Qt.darker(root.barForeground, 1.55)

          Behavior on color {
            ColorAnimation { duration: Style.duration(160) }
          }
        }
      }
    }
    onPressed: function(pressedButton) {
      if (pressedButton === Qt.RightButton) root.playPause()
      else if (pressedButton === Qt.MiddleButton) root.skip(1)
      else root.toggle()
    }
  }

  // ------------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onActivateRequested: root.playPause()
      // The catcher flips Left and Right for right-to-left languages, but the
      // transport stays left to right, so flip them back.
      onMoveRequested: function(dx, dy) { if (dx !== 0) root.skip(Commons.I18n.rightToLeft ? -dx : dx) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(12)
        // Timelines and transport read left to right in every language.
        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true

        // Artwork, track, level.
        Item {
          width: parent.width
          height: Style.space(56)

          // A blurred copy of the artwork behind it, so the glow is the cover's
          // own colours and follows its crossfade. It stops inside the card's
          // padding, and softens while paused.
          MultiEffect {
            anchors.fill: artFrame
            anchors.margins: Style.space(1)
            source: artStack
            visible: String(root.artUrl) !== ""
            autoPaddingEnabled: false
            // Tighter on the sides next to the card edge, so it never spills out.
            paddingRect: Qt.rect(root.glowReach, root.glowReach, root.glowReach * 3, root.glowReach * 3)
            blurEnabled: true
            blur: 1
            blurMax: 26
            saturation: 0.35
            opacity: root.isPlaying ? 0.95 : 0.45

            Behavior on opacity {
              NumberAnimation { duration: Style.duration(280); easing.type: Easing.OutCubic }
            }
          }

          BorderSurface {
            id: artFrame
            width: parent.height
            height: parent.height
            radius: Style.cornerRadius
            color: Style.normalFillFor(root.foreground, Commons.Color.accent)
            borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)

            NowPlayingIcon {
              anchors.centerIn: parent
              iconSize: Style.space(24)
              raised: true
              color: root.dim
              visible: String(artBack.url) === "" && artFront.opacity === 0
            }

            // The new artwork fades in over the old once it has loaded, so the
            // frame never flashes empty while it downloads.
            Item {
              id: artStack
              anchors.fill: parent
              anchors.margins: Style.space(1)

              SizedImage {
                id: artBack
                anchors.fill: parent
                crop: true
                Component.onCompleted: url = root.artUrl
              }

              SizedImage {
                id: artFront
                anchors.fill: parent
                crop: true
                opacity: 0
                scale: 0.97
                onStatusChanged: if (status === Image.Ready && String(url) !== "" && String(url) !== String(artBack.url)) artFade.restart()
              }
            }

            Connections {
              target: root
              function onArtUrlChanged() {
                artFade.stop()
                artFront.opacity = 0
                artFront.scale = 0.97
                if (String(root.artUrl) === "") {
                  artBack.url = ""
                  artFront.url = ""
                } else {
                  artFront.url = root.artUrl
                }
              }
            }

            SequentialAnimation {
              id: artFade
              ParallelAnimation {
                NumberAnimation { target: artFront; property: "opacity"; to: 1; duration: Style.duration(220); easing.type: Easing.OutCubic }
                NumberAnimation { target: artFront; property: "scale"; to: 1; duration: Style.duration(220); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
              }
              ScriptAction {
                script: {
                  artBack.url = artFront.url
                  artFront.opacity = 0
                  artFront.scale = 0.97
                }
              }
            }
          }

          Row {
            id: meter
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: Style.space(16)
            spacing: Style.space(2)

            Repeater {
              model: root.barCount

              Item {
                required property int index
                width: Style.space(2)
                height: meter.height

                Rectangle {
                  anchors.bottom: parent.bottom
                  width: parent.width
                  height: Math.max(Style.space(2), parent.height * (root.levels[parent.index] || 0))
                  color: root.isPlaying ? root.foreground : root.dim

                  Behavior on height {
                    NumberAnimation { duration: Style.duration(90); easing.type: Easing.OutCubic }
                  }
                  Behavior on color {
                    ColorAnimation { duration: Style.duration(160) }
                  }
                }
              }
            }
          }

          Column {
            anchors.left: artFrame.right
            anchors.leftMargin: Style.space(12)
            anchors.right: meter.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)
            opacity: root.infoOpacity
            transform: Translate { x: root.infoShift }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.shownTitle || strings.t("unknownTitle")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.shownArtist
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: root.shownSource
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }
        }

        // Timeline. Thin at rest, thicker with a handle when it can be grabbed.
        Column {
          width: parent.width
          spacing: Style.space(3)

          Item {
            id: scrubber
            width: parent.width
            height: Style.space(12)

            property bool dragging: false
            property real dragFraction: 0
            readonly property bool hot: root.canSeek && (scrubArea.containsMouse || dragging)
            readonly property real fraction: dragging ? dragFraction : root.progress

            Rectangle {
              id: track
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: Style.space(scrubber.hot ? 4 : 2)
              color: Style.selectedFillFor(root.foreground, Commons.Color.accent)

              Behavior on height {
                NumberAnimation { duration: Style.duration(110); easing.type: Easing.OutCubic }
              }
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              height: track.height
              width: track.width * scrubber.fraction
              color: root.foreground

              // Steady motion between position readings, so it is linear.
              Behavior on width {
                enabled: !scrubber.dragging && root.isPlaying && !swapAnimation.running
                NumberAnimation { duration: Style.duration(500); easing.type: Easing.Linear }
              }
            }

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              x: Math.max(0, Math.min(track.width - width, track.width * scrubber.fraction - width / 2))
              width: Style.space(4)
              height: Style.space(12)
              color: root.foreground
              opacity: scrubber.hot ? 1 : 0

              Behavior on opacity {
                NumberAnimation { duration: Style.duration(110); easing.type: Easing.OutCubic }
              }
            }

            MouseArea {
              id: scrubArea
              anchors.fill: parent
              hoverEnabled: true
              enabled: root.canSeek
              cursorShape: root.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
              onPressed: function(mouse) {
                scrubber.dragFraction = MusicModel.clampFraction(mouse.x / width)
                scrubber.dragging = true
              }
              onPositionChanged: function(mouse) {
                if (scrubber.dragging) scrubber.dragFraction = MusicModel.clampFraction(mouse.x / width)
              }
              onReleased: {
                root.seekTo(scrubber.dragFraction)
                scrubber.dragging = false
              }
              onCanceled: scrubber.dragging = false
            }
          }

          Item {
            width: parent.width
            height: elapsedLabel.implicitHeight

            Text {
              id: elapsedLabel
              textFormat: Text.PlainText
              text: root.length > 0 ? MusicModel.formatTime(scrubber.fraction * root.length) : "--:--"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              textFormat: Text.PlainText
              text: root.length > 0 ? "-" + MusicModel.formatTime((1 - scrubber.fraction) * root.length) : "--:--"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }

        // Transport.
        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(10)

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: String.fromCodePoint(0xF04AE)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconSize: Style.font.icon
            verticalPadding: Style.space(3)
            tooltipText: strings.t("previous")
            enabled: !!root.player && root.player.canGoPrevious
            opacity: enabled ? 1 : 0.4
            onClicked: root.skip(-1)
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: String.fromCodePoint(root.isPlaying ? 0xF03E4 : 0xF040A)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconSize: Style.font.iconLarge
            verticalPadding: Style.space(3)
            horizontalPadding: Style.spacing.panelGap
            tooltipText: strings.t("playPause")
            enabled: MusicModel.canPlayPause(root.player)
            opacity: enabled ? 1 : 0.4
            onClicked: root.playPause()
          }

          Button {
            anchors.verticalCenter: parent.verticalCenter
            iconText: String.fromCodePoint(0xF04AD)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconSize: Style.font.icon
            verticalPadding: Style.space(3)
            tooltipText: strings.t("next")
            enabled: !!root.player && root.player.canGoNext
            opacity: enabled ? 1 : 0.4
            onClicked: root.skip(1)
          }
        }

        // Only there when more than one music player is open.
        PanelSeparator {
          visible: root.musicPlayers.length > 1
          foreground: root.foreground
        }

        Flow {
          visible: root.musicPlayers.length > 1
          width: parent.width
          spacing: Style.space(4)

          Repeater {
            model: root.musicPlayers.length > 1 ? root.musicPlayers : []

            Button {
              required property var modelData
              text: modelData.identity || modelData.desktopEntry || ""
              foreground: root.foreground
              fontFamily: root.fontFamily
              fontSize: Style.font.caption
              selected: modelData === root.player
              onClicked: root.pinnedKey = MusicModel.playerKey(modelData)
            }
          }
        }
      }
    }
  }
}
