// Run with: node tests/model.test.js
const fs = require("fs"), path = require("path"), vm = require("vm"), assert = require("assert")
const m = {}
vm.createContext(m)
vm.runInContext(fs.readFileSync(path.join(__dirname, "..", "MusicModel.js"), "utf8"), m)

const p = (o) => Object.assign({ trackTitle: "Song", trackArtist: "", trackAlbum: "", metadata: {} }, o)
const url = (u) => ({ metadata: { "xesam:url": u } })
const check = (name, player, want) => assert.strictEqual(m.isMusic(player, []), want, name)

check("spotify", p({ desktopEntry: "spotify", identity: "Spotify" }), true)
check("cider", p({ identity: "Cider" }), true)
check("spotify with no track", p({ desktopEntry: "spotify", trackTitle: "" }), false)
check("playerctld proxy", p({ dbusName: "org.mpris.MediaPlayer2.playerctld", trackAlbum: "A", trackArtist: "B" }), false)

const vivaldi = { desktopEntry: "vivaldi-stable", identity: "Vivaldi" }
check("apple music web", p({ ...vivaldi, ...url("https://music.apple.com/in/album/x") }), true)
check("youtube music web", p({ ...vivaldi, ...url("https://music.youtube.com/watch?v=1") }), true)
check("youtube video by url", p({ ...vivaldi, trackArtist: "Channel", trackAlbum: "x", ...url("https://www.youtube.com/watch?v=1") }), false)
check("lookalike host", p({ ...vivaldi, ...url("https://music.apple.com.evil.example/x") }), false)
check("browser music, no url", p({ ...vivaldi, trackArtist: "Artist", trackAlbum: "Album" }), true)
check("browser video, no url", p({ ...vivaldi, trackArtist: "Channel" }), false)

const mpv = { identity: "mpv", desktopEntry: "mpv" }
check("mpv with a flac", p({ ...mpv, ...url("file:///home/user/Music/a%20b.flac") }), true)
check("mpv with a film", p({ ...mpv, trackArtist: "A", trackAlbum: "B", ...url("file:///home/user/film.mkv") }), false)
check("unknown app, no evidence", p({ identity: "Thing" }), false)
assert.strictEqual(m.isMusic(p({ identity: "Thing" }), m.parseExtraPlayers(" thing , other")), true, "extra player")

check("name inside a longer word", p({ identity: "Skew Viewer" }), false)
check("short app name on its own", p({ identity: "kew" }), true)
check("name in a reverse-DNS id", p({ desktopEntry: "io.bassi.Amberol" }), true)
assert.strictEqual(m.isMusic(p({ identity: "Foo (bar)" }), ["foo (bar)"]), true, "extra name with regex characters")

const a = p({ dbusName: "a", isPlaying: false }), b = p({ dbusName: "b", isPlaying: true }), c = p({ dbusName: "c", isPlaying: true })
assert.strictEqual(m.selectActive([a, b], ""), b, "playing wins")
assert.strictEqual(m.selectActive([a, b], "a"), b, "playing beats paused preference")
assert.strictEqual(m.selectActive([b, c], "c"), c, "preference wins between playing")
assert.strictEqual(m.selectActive([a], "gone"), a, "falls back")
assert.strictEqual(m.selectActive([], ""), null, "empty")
assert.strictEqual(m.selectActive([a, b], "", "a"), a, "a pinned paused player beats a playing one")
assert.strictEqual(m.selectActive([b], "", "gone"), b, "a pinned player that left is ignored")

assert.strictEqual(m.safeArtUrl("javascript:alert(1)"), "", "art scheme")
assert.strictEqual(m.safeArtUrl("https://i.scdn.co/a"), "https://i.scdn.co/a", "art https")
assert.strictEqual(m.formatTime(65), "1:05")
assert.strictEqual(m.formatTime(3725), "1:02:05")
assert.strictEqual(m.formatTime(NaN), "--:--")
assert.strictEqual(m.barLevel(0.5, 0.5), 1, "at the ceiling")
assert.strictEqual(m.barLevel(0.25, 0.5), 0.125, "swings are curved")
assert.strictEqual(m.barLevel(0, m.nextCeiling(0, 0)), 0, "silence")
assert.ok(m.barLevel(0.001, m.nextCeiling(0.001, 0)) < 0.001, "noise stays low")
assert.strictEqual(m.nextCeiling(0.8, 0.2), 0.8, "ceiling rises at once")
assert.ok(m.nextCeiling(0.1, 0.8) > 0.79, "ceiling falls slowly")
const nums = (path) => path.trim().split(/\s+/).map((part) => parseFloat(part.replace(/[ML]/, "")))
const ys = (path) => nums(path).filter((_, i) => i % 2 === 1)
const xs = (path) => nums(path).filter((_, i) => i % 2 === 0)
const g15 = m.waveGrid(15)
assert.deepStrictEqual([g15.stroke, g15.middle], [2, 8], "15 px box: 2 px stroke covering rows 7 and 8")
for (const px of [12, 15, 18, 20, 24, 30, 36]) {
  const g = m.waveGrid(px)
  assert.ok(Number.isInteger(g.stroke), "whole-pixel stroke at " + px)
  assert.ok(Number.isInteger(g.middle - g.stroke / 2), "paused line covers whole rows at " + px)
  for (let phase = 0; phase < 6.3; phase += 0.1) {
    const path = m.wavePath(g, 1, phase, 1), y = ys(path)
    assert.ok(Math.min(...y) - g.stroke / 2 >= -1e-9 && Math.max(...y) + g.stroke / 2 <= g.size + 1e-9,
      "wave ink stays in a " + px + " px box at phase " + phase)
    assert.strictEqual(y[0], g.middle, "wave starts on the centre line")
    assert.strictEqual(y[y.length - 1], g.middle, "wave ends on the centre line")
    assert.ok(Math.min(...xs(path)) - g.stroke / 2 >= 0 && Math.max(...xs(path)) + g.stroke / 2 <= g.size, "caps stay in the box")
  }
}
assert.ok(ys(m.wavePath(g15, 0, 1.2, 1)).every((y) => y === 8), "paused wave is flat")
// Steep slopes made the two sides of a peak run together into a blob at
// icon size. Keep the swing to 4 px and the slope gentle at every phase.
for (let phase = 0; phase < 6.3; phase += 0.05) {
  const n = nums(m.wavePath(g15, 1, phase, 1))
  for (let i = 2; i < n.length; i += 2) {
    assert.ok(Math.abs(n[i + 1] - g15.middle) <= 4 + 1e-9, "15 px wave swings at most 4 px at phase " + phase)
    assert.ok(Math.abs((n[i + 1] - n[i - 1]) / (n[i] - n[i - 2])) <= 2.5, "15 px wave slope stays gentle at phase " + phase)
  }
}
assert.notStrictEqual(m.wavePath(g15, 1, 0, 1), m.wavePath(g15, 1, 1, 1), "phase moves the wave")
assert.ok(ys(m.wavePath(g15, 0, 0, 0.8)).every((y) => y === 6.4), "unit scales device pixels to item units")
assert.ok(Math.abs(m.pixelSnap(10, 1.25) - 0.4) < 1e-9, "12.5 device px shifts half a pixel to 13")
assert.strictEqual(m.pixelSnap(8, 1.25), 0, "already on the grid")
assert.ok([3.3, 7.77, 101.1].every((p) => Number.isInteger(Math.round((p + m.pixelSnap(p, 1.25)) * 1.25 * 1e6) / 1e6)), "snapped points land on whole device pixels")
assert.deepStrictEqual(Array.from(m.silentLevels(3)), [0, 0, 0], "silent ring")
const ringPts = (p) => { const n = nums(p.replace("Z", "")); const out = []; for (let i = 0; i < n.length; i += 2) out.push(Math.hypot(n[i] - 24, n[i + 1] - 24)); return out }
assert.ok(ringPts(m.ringPath(24, 24, 18, 0, 1, 6)).every((r) => Math.abs(r - 18) < 0.01), "quiet ring is a circle")
for (let phase = 0; phase < 6.3; phase += 0.3) {
  const rs = ringPts(m.ringPath(24, 24, 18, 4, phase, 9))
  assert.ok(Math.max(...rs) <= 22.01 && Math.min(...rs) >= 13.99, "ring stays within its swing at phase " + phase)
}
assert.ok(m.ringPath(24, 24, 18, 3, 0, 6).trim().endsWith("Z"), "ring is closed")
assert.notStrictEqual(m.ringPath(24, 24, 18, 3, 0, 6), m.ringPath(24, 24, 18, 3, 1, 6), "phase moves the ring")
assert.strictEqual(m.ringPath(24, 24, 18, 3, 0, 6), m.ringPath(24, 24, 18, 3, 2 * Math.PI * 2, 6).replace(/-0\.00/g, "0.00"), "ring loops without a jump")
assert.ok(m.advancePhase(6.2, 100) < 2 * Math.PI, "phase wraps")
assert.strictEqual(m.advancePhase(1, 60000), m.advancePhase(1, 250), "a long gap does not jump")
assert.strictEqual(m.isRemoteArt("https://i.scdn.co/a"), true, "https art is remote")
assert.strictEqual(m.isRemoteArt("file:///a.png"), false, "file art is local")
assert.notStrictEqual(m.artFileName("https://a/1"), m.artFileName("https://a/2"), "different covers, different files")
assert.ok(/^cover-[0-9a-f]+\.img$/.test(m.artFileName("https://a/../../etc/passwd")), "nothing from the URL reaches the path")
console.log("ok")
