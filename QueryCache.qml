import QtQuick

import "Api.js" as Api

// Answers we already have, kept so a page you reopen draws immediately and the
// fresh copy arrives behind it. Spotify's budget is shared with every other app
// on the same client id, so the cheapest request is the one never sent.
// Deliberately free of Quickshell types so it can be unit tested: the service
// hands it the clock and does the saving.
Item {
  id: cache

  visible: false
  width: 0
  height: 0

  property var entries: ({})
  property var order: []
  // How many pages are remembered, and how many rows of each.
  property int limit: 24
  property int itemLimit: 200
  // How long an answer counts as current. Past this it is still drawn, but a
  // fresh one is fetched behind it.
  property int staleMs: 300000
  // Past this it is not worth drawing at all.
  property int maxAgeMs: 604800000
  property var running: ({})
  property var now: function() { return Date.now() }

  signal changed()

  function freshness(key) {
    return Api.queryCacheState(entries[String(key || "")], now(), staleMs)
  }

  function read(key) {
    var entry = entries[String(key || "")]
    return Api.queryCacheState(entry, now(), maxAgeMs) === "missing"
      ? null : entry.data
  }

  function write(key, data) {
    if (!Api.pageSnapshotHasContent(data)) return
    keep(key, Api.cappedPageSnapshot(data, itemLimit), now())
    changed()
  }

  function drop(key) {
    if (!entries.hasOwnProperty(String(key || ""))) return
    var next = Api.dropQueryEntry(entries, order, key)
    entries = next.entries
    order = next.order
    changed()
  }

  function clear() {
    entries = ({})
    order = []
    running = ({})
    changed()
  }

  // Two lists asking for the same page at once should make one request.
  function beginFetch(key) {
    var name = String(key || "")
    if (!name || running[name] === true) return false
    running[name] = true
    return true
  }

  function endFetch(key) {
    delete running[String(key || "")]
  }

  function serialize() {
    return Api.encodeQueryCache(entries, order)
  }

  // Anything written since launch is newer than the file, so it is put back
  // last and survives if the two together overflow the limit.
  function restore(raw) {
    var stored = Api.parseQueryCache(raw, now(), maxAgeMs)
    var held = []
    var i
    for (i = 0; i < order.length; i++) held.push(entries[order[i]])
    var names = order.slice()
    for (i = 0; i < stored.order.length; i++) {
      var key = stored.order[i]
      if (entries.hasOwnProperty(key)) continue
      keep(key, stored.entries[key].data, stored.entries[key].updatedAt)
    }
    for (i = 0; i < names.length; i++)
      keep(names[i], held[i].data, held[i].updatedAt)
  }

  function keep(key, data, updatedAt) {
    var next = Api.putQueryEntry(entries, order, key, data, updatedAt, limit)
    entries = next.entries
    order = next.order
  }
}
