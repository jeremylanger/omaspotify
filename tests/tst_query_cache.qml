import QtQuick
import QtTest

import ".."

TestCase {
  id: testCase
  name: "QueryCache"

  property double clock: 10000
  property int changes: 0

  QueryCache {
    id: cache
    limit: 3
    staleMs: 1000
    maxAgeMs: 100000
    now: function() { return testCase.clock }
    onChanged: testCase.changes += 1
  }

  function init() {
    cache.clear()
    clock = 10000
    changes = 0
  }

  function test_anUnknownPageHasNothingToDraw() {
    compare(cache.freshness("detail:album:one"), "missing")
    compare(cache.read("detail:album:one"), null)
  }

  function test_aWrittenPageIsDrawnBackWhole() {
    cache.write("detail:album:one", { item: { id: "one" }, items: [1, 2] })
    compare(cache.freshness("detail:album:one"), "fresh")
    compare(cache.read("detail:album:one").items.length, 2)
    compare(changes, 1, "the cache says when it is worth saving")
  }

  function test_aPageGoesStaleAndIsStillDrawn() {
    cache.write("detail:album:one", { item: { id: "one" }, items: [1] })
    clock += 999
    compare(cache.freshness("detail:album:one"), "fresh")
    clock += 2
    compare(cache.freshness("detail:album:one"), "stale")
    compare(cache.read("detail:album:one").items.length, 1,
      "a stale page is still worth drawing while the fresh one loads")
  }

  function test_theOldestPageFallsOffTheEnd() {
    cache.write("a", { item: { id: "a" }, items: [1] })
    cache.write("b", { item: { id: "b" }, items: [1] })
    cache.write("c", { item: { id: "c" }, items: [1] })
    cache.write("d", { item: { id: "d" }, items: [1] })
    compare(cache.freshness("a"), "missing")
    compare(cache.freshness("d"), "fresh")
  }

  function test_droppingAPageForgetsIt() {
    cache.write("a", { item: { id: "a" }, items: [1] })
    cache.drop("a")
    compare(cache.freshness("a"), "missing")
    cache.drop("never-there")
    compare(cache.freshness("a"), "missing")
  }

  // Two things asking for the same page at once should make one request.
  function test_onlyOneFetchPerPageAtATime() {
    verify(cache.beginFetch("a"))
    verify(!cache.beginFetch("a"), "the second caller is told one is running")
    verify(cache.beginFetch("b"))
    cache.endFetch("a")
    verify(cache.beginFetch("a"))
  }

  function test_clearingForgetsEverythingIncludingWhatIsInFlight() {
    cache.write("a", { item: { id: "a" }, items: [1] })
    verify(cache.beginFetch("a"))
    cache.clear()
    compare(cache.freshness("a"), "missing")
    verify(cache.beginFetch("a"), "a cleared cache is not still waiting")
  }

  function test_theCacheSurvivesARestart() {
    cache.write("a", { item: { id: "a" }, items: [1, 2] })
    var saved = cache.serialize()
    cache.clear()
    compare(cache.freshness("a"), "missing")
    cache.restore(saved)
    compare(cache.freshness("a"), "fresh")
    compare(cache.read("a").items.length, 2)
  }

  function test_aPageCachedBeforeTheFileLoadedIsNotLostToIt() {
    cache.write("a", { item: { id: "a" }, items: [1] })
    cache.write("b", { item: { id: "b" }, items: [1] })
    cache.write("c", { item: { id: "c" }, items: [1] })
    var saved = cache.serialize()
    cache.clear()
    cache.write("fresh", { item: { id: "fresh" }, items: [1] })
    cache.restore(saved)
    compare(cache.freshness("fresh"), "fresh", "what this run cached is kept")
    compare(cache.freshness("c"), "fresh")
    compare(cache.freshness("a"), "missing", "the oldest page from the file goes")
  }

  function test_aRestoredPageTooOldToTrustIsDropped() {
    cache.write("a", { item: { id: "a" }, items: [1] })
    var saved = cache.serialize()
    cache.clear()
    clock += 200000
    cache.restore(saved)
    compare(cache.freshness("a"), "missing")
  }

  function test_aHalfLoadedPageIsNotWorthKeeping() {
    cache.write("a", { item: { id: "a" }, items: [] })
    compare(cache.freshness("a"), "missing")
    cache.write("b", null)
    compare(cache.freshness("b"), "missing")
  }

  function test_aLongPageIsTrimmedBeforeItIsKept() {
    cache.itemLimit = 2
    cache.write("a", { item: { id: "a" }, items: [1, 2, 3], next: "cursor" })
    compare(cache.read("a").items.length, 2)
    compare(cache.read("a").next, "")
    cache.itemLimit = 200
  }
}
