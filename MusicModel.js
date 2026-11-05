// What counts as music, kept apart from the UI so it can be tested on its own.
//
// MPRIS has no "this is music" field. Known music apps always count. Anything
// else, browsers and video players included, has to show evidence: an audio
// file, a known music site, or an album and artist on the track.

var MUSIC_APPS = [
  "spotify", "spotify-player", "spotifyd", "ncspot", "cider", "apple-music", "apple music",
  "tidal", "tidal-hifi", "deezer", "qobuz", "plexamp", "youtube-music", "youtube music",
  "pear-desktop", "feishin", "sonixd", "supersonic", "nuclear", "rhythmbox", "lollypop",
  "amberol", "strawberry", "clementine", "elisa", "audacious", "deadbeef", "quodlibet",
  "quod libet", "tauon", "museeks", "gapless", "g4music", "cmus", "musikcube", "termusic",
  "mopidy", "mpd", "mpdris", "kew", "gmusicbrowser", "sayonara", "juk", "cantata", "harmonoid"
]

var MUSIC_HOSTS = [
  "music.apple.com", "open.spotify.com", "music.youtube.com", "soundcloud.com", "tidal.com",
  "deezer.com", "bandcamp.com", "pandora.com", "music.amazon.com", "qobuz.com", "last.fm",
  "mixcloud.com", "jiosaavn.com", "gaana.com", "wynk.in"
]

var AUDIO_FILE = /\.(mp3|flac|ogg|oga|opus|m4a|aac|wav|wma|aiff?|alac|ape|wv|mpc|dsf)$/i
var VIDEO_FILE = /\.(mp4|mkv|webm|avi|mov|wmv|flv|m4v|mpe?g|ts|ogv)$/i

function playerNames(player) {
  return [player && player.desktopEntry, player && player.identity, player && player.dbusName]
    .map(function(name) { return String(name || "").toLowerCase() })
    .join(" ")
}

// Whole names only, so "kew" doesn't match "skew". The names come from player
// metadata and user settings, so this compares text rather than building a regex.
function isNameBoundary(names, index) {
  return index < 0 || index >= names.length || !/[a-z0-9]/.test(names.charAt(index))
}

function matchesAny(names, list) {
  for (var i = 0; i < list.length; i++) {
    var name = list[i]
    var at = names.indexOf(name)
    while (at !== -1) {
      if (isNameBoundary(names, at - 1) && isNameBoundary(names, at + name.length)) return true
      at = names.indexOf(name, at + 1)
    }
  }
  return false
}

function isProxy(player) {
  return playerNames(player).indexOf("playerctld") !== -1
}

function hasTrack(player) {
  return !!(player && (player.trackTitle || player.trackArtist))
}

function trackUrl(player) {
  var metadata = player && player.metadata
  var url = metadata ? metadata["xesam:url"] : ""
  return String(url || "")
}

function urlPath(url) {
  return url.split(/[?#]/)[0]
}

function urlHost(url) {
  var match = /^[a-z][a-z0-9+.-]*:\/\/(?:[^\/@]*@)?([^\/:?#]+)/i.exec(url)
  return match ? match[1].toLowerCase() : ""
}

function isMusicHost(host) {
  for (var i = 0; i < MUSIC_HOSTS.length; i++) {
    var known = MUSIC_HOSTS[i]
    if (host === known || host.slice(-(known.length + 1)) === "." + known) return true
  }
  return false
}

function parseExtraPlayers(value) {
  return String(value || "")
    .split(",")
    .map(function(name) { return name.replace(/^\s+|\s+$/g, "").toLowerCase() })
    .filter(function(name) { return name.length > 0 })
}

function isMusic(player, extraPlayers) {
  if (!player || isProxy(player) || !hasTrack(player)) return false

  var names = playerNames(player)
  if (matchesAny(names, MUSIC_APPS) || matchesAny(names, extraPlayers || [])) return true

  var url = trackUrl(player)
  var path = urlPath(url)
  if (AUDIO_FILE.test(path)) return true
  if (VIDEO_FILE.test(path)) return false

  var host = urlHost(url)
  if (host) return isMusicHost(host)

  // No usable URL, which is the usual case for Chromium browsers. Music sites
  // fill in the album; a regular YouTube video reports only the channel.
  return !!(player.trackAlbum && player.trackArtist)
}

function musicPlayers(players, extraPlayers) {
  var list = []
  for (var i = 0; i < (players ? players.length : 0); i++) {
    if (isMusic(players[i], extraPlayers)) list.push(players[i])
  }
  return list
}

function playerKey(player) {
  return player ? String(player.dbusName || player.uniqueId || player.identity || "") : ""
}

// A player picked in the switcher stays while it exists. Otherwise a playing
// player beats a paused one, and the player last used beats the others in its group.
function selectActive(players, preferredKey, pinnedKey) {
  var preferred = null
  var playing = null
  for (var i = 0; i < players.length; i++) {
    var player = players[i]
    var key = playerKey(player)
    if (pinnedKey && key === pinnedKey) return player
    if (preferredKey && key === preferredKey) preferred = player
    if (!playing && player.isPlaying) playing = player
  }
  if (preferred && preferred.isPlaying) return preferred
  return playing || preferred || players[0] || null
}

function canPlayPause(player) {
  return !!(player && (player.canTogglePlaying || player.canPlay || player.canPause))
}

// Only images from the places a player legitimately serves them.
function safeArtUrl(url) {
  var value = String(url || "")
  return /^(https?|file):\/\//i.test(value) ? value : ""
}

function isRemoteArt(url) {
  return /^https?:\/\//i.test(String(url || ""))
}

// A filename for a downloaded cover. Different covers need different names, or
// the image cache would keep showing the old one. This deliberately avoids
// Qt.md5, which goes through the same crypto library as the crash noted in
// Panel.qml, and it can't carry anything from the URL into the path.
function artFileName(url) {
  var text = String(url || "")
  var hash = 5381
  for (var i = 0; i < text.length; i++) hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0
  return "cover-" + hash.toString(16) + ".img"
}

function formatTime(seconds) {
  if (!isFinite(seconds) || seconds < 0) return "--:--"
  var total = Math.floor(seconds)
  var h = Math.floor(total / 3600)
  var m = Math.floor((total % 3600) / 60)
  var s = total % 60
  var ss = (s < 10 ? "0" : "") + s
  if (h > 0) return h + ":" + (m < 10 ? "0" : "") + m + ":" + ss
  return m + ":" + ss
}

function clampFraction(value) {
  return !isFinite(value) ? 0 : Math.max(0, Math.min(1, value))
}

// Mastered music sits close to its ceiling, so raw peaks would hold every bar
// near the top. Levels are measured against a slowly falling recent maximum,
// then curved so the swings show at any volume. The floor keeps noise low.
function nextCeiling(peak, ceiling) {
  return Math.max(clampFraction(peak), (ceiling || 0) * 0.99, 0.02)
}

function barLevel(peak, ceiling) {
  return Math.pow(clampFraction(peak / (ceiling || 1)), 3)
}

// One trip along the wave takes this long.
var WAVE_PERIOD_MS = 3200

function advancePhase(phase, elapsedMs) {
  // A long gap, such as waking from sleep, carries on instead of jumping.
  var step = Math.min(Math.max(0, elapsedMs), 250) / WAVE_PERIOD_MS
  return (phase + step * 2 * Math.PI) % (2 * Math.PI)
}

// The wave as an SVG path inside a size-by-size box. A second, faster ripple
// keeps it from reading as a plain sine, and the envelope pins both ends to
// the centre line. Peak height stays inside the box at every phase.
function wavePath(size, amplitude, phase) {
  var points = 16
  var inset = size / 8
  var width = size - inset * 2
  var middle = size / 2
  var reach = (size / 2 - inset) * clampFraction(amplitude)
  var path = ""
  for (var i = 0; i <= points; i++) {
    var t = i / points
    var envelope = Math.sin(Math.PI * t)
    var wave = 0.85 * Math.sin(2 * Math.PI * 1.25 * t - phase)
      + 0.15 * Math.sin(2 * Math.PI * 2.5 * t - phase * 2)
    var x = inset + width * t
    var y = middle + reach * envelope * wave
    path += (i === 0 ? "M" : "L") + x.toFixed(2) + " " + y.toFixed(2) + " "
  }
  return path
}
