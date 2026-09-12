import QtQuick
import QtTest
import ".." as Plugin
TestCase {
  id: testCase
  name: "FilterScan"
  Component { id: scanner; Plugin.FilterScanController {} }
  function test_budgetPausesAndManualContinueResetsIt() {
    var scan = createTemporaryObject(scanner, testCase, {active: true, query: "song", hasMore: true, pageBudget: 2})
    var calls = 0
    scan.requestNext.connect(function() { calls++; scan.loading = true })
    scan.step()
    compare(calls, 1)
    scan.step()
    compare(calls, 1)
    scan.itemCount = 50
    scan.loading = false
    scan.step()
    compare(calls, 2)
    scan.itemCount = 100
    scan.loading = false
    scan.step()
    verify(scan.paused)
    scan.resume()
    scan.step()
    compare(calls, 3)
    scan.active = false
    scan.loading = false
    scan.step()
    compare(calls, 3)
  }
  function test_noProgressAndErrorsDoNotLoop() {
    var scan = createTemporaryObject(scanner, testCase, {active: true, query: "song", hasMore: true})
    var calls = 0
    scan.requestNext.connect(function() { calls++ })
    scan.step()
    scan.step()
    compare(calls, 1)
    verify(scan.paused)
    scan.query = "new"
    scan.blocked = true
    scan.step()
    compare(calls, 1)
  }
}
