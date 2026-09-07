import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui

import "Api.js" as Api

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var service: null
  property bool opened: false
  property bool closingFromHost: false
  property bool escapeCloseArmed: false
  property real volumeBeforeMute: 0.5
  property double lastVolumeAdjustAt: 0
  property string currentTab: "home"
  property bool openedForLogin: false

  property string searchText: ""
  property string searchType: "track"
  property string libraryType: "tracks"
  property string homeType: "recent"
  property string libraryFilter: ""
  property string librarySort: "default"
  property string playlistFilter: ""
  property string playlistSort: "default"
  property string detailFilter: ""
  property string detailSort: "default"
  property string homeFilter: ""
  property string discoverFilter: ""
  property string queueFilter: ""
  property string artistSearchText: ""
  property bool searchInContext: true
  property bool universalSearchActive: false
  property var scrollPositions: ({})
  property var scrollPositionOrder: []
  readonly property int scrollPositionLimit: 128
  property var navigationStack: []
  property string lastContentTab: "home"
  property string restoredPlaylistId: ""
  property var restoredPlaylist: null
  property int restoredPlaylistItemCount: 0
  property int restoredDetailItemCount: 0

  property string draftDeviceName: "OmaSpotify"
  property string draftIdleMinutes: "15"
  property bool draftShowMiniPlayer: true
  property string draftShortcutPlayer: "Omarchy Music app"
  property bool draftShortcutHints: true
  property bool shortcutModeLatched: false
  property int heldModifierFlags: 0
  property bool panelCursorActive: false
  property string panelCursorRegion: "footer"
  property string panelCursorAction: "play"
  property string popupReturnRegion: "page"
  property string popupReturnAction: "list"
  property bool draftShowTitle: true
  property bool draftShowArtist: false
  property bool draftShowPausedTrack: true
  property bool draftScrollBarText: false
  property real draftScrollSpeed: 1
  // 0 means no cap — the slot grows with the track text.
  property real draftMaxBarTextWidth: 240
  // Disclosure state for the width slider; deliberately not persisted.
  property bool barTextWidthExpanded: false
  property string draftAudioQuality: "320 kbps"
  property bool draftNormalizeVolume: true
  property string draftVolumeLevel: "Normal"
  property var contextItem: null
  property var contextSourceItems: []
  property string contextSourceUri: ""
  property string contextPlaybackUri: ""
  property int contextSourceIndex: -1
  property var contextPlaylist: null
  property var pendingPlaylistItem: null
  property string newPlaylistName: ""
  property string createPlaylistName: ""

  readonly property string pluginId: manifest && manifest.id
    ? String(manifest.id) : "io.github.jeremylanger.omaspotify"
  readonly property string appName: manifest && manifest.name
    ? String(manifest.name) : "OmaSpotify"
  readonly property string lyricsRequestKey: "spotify-panel-lyrics"
  readonly property color foreground: Color.foreground
  readonly property color background: Color.background
  readonly property color accent: Color.accent
  readonly property color muted: Color.muted
  readonly property color popupBackground: Color.popups.background
  readonly property var popupBorderSpec: Border.flat(Color.popups.border,
    Math.max(1, Style.normalBorderWidth))
  readonly property int popupScrollbarGutter: Style.space(14)
  readonly property string fontFamily: Style.font.family
  readonly property bool fullyConnected: service && service.fullyConnected
  readonly property bool accountConnected: service && service.accountConnected
  readonly property bool sessionPending: service && service.sessionPending
  readonly property bool compactHeight: window.height < Style.space(620)
  readonly property bool compactWidth: window.width < Style.space(760)
  readonly property var activeSearchScope: Api.searchScope(currentTab,
    service ? service.detailItem : null,
    service ? service.selectedPlaylist : null, homeType, libraryType)
  readonly property bool showingUniversalSearch: Api.universalSearchVisible(
    currentTab, universalSearchActive)
  readonly property bool artistScopedSearchActive: currentTab === "detail"
    && service && service.detailItem && service.detailItem.type === "artist"
    && artistSearchText.trim() !== ""
  readonly property bool shortcutsBlocked: mediaContextMenu.opened
    || playlistPicker.opened || createPlaylistPopup.opened || sleepPopup.opened
    || shortcutHelpPopup.opened || lyricsInstallPopup.opened
  readonly property bool shortcutHintsEnabled: service
    ? service.shortcutHintsEnabled : true
  readonly property bool typingInField: {
    var item = window.activeFocusItem
    return !!item && ("acceptableInput" in item || "echoMode" in item)
  }
  readonly property bool shortcutHintsActive: shortcutHintsEnabled
    && shortcutModeLatched && !typingInField && !shortcutsBlocked
  readonly property bool shortcutHintsInPopup: shortcutHintsEnabled
    && shortcutModeLatched && !typingInField
  readonly property var windowContentItem: window.contentItem
  readonly property real windowWidth: window.width
  readonly property real windowHeight: window.height
  readonly property int playlistShortcutIndex: playlistShortcuts.currentIndex
  readonly property bool searchFieldFocused: unifiedSearchField.activeFocus
  readonly property bool hintCtrlHeld: (heldModifierFlags & Qt.ControlModifier) !== 0
  readonly property bool hintShiftHeld: (heldModifierFlags & Qt.ShiftModifier) !== 0
  readonly property bool hintAltHeld: (heldModifierFlags & Qt.AltModifier) !== 0
  readonly property bool popupCursorOpen: sleepPopup.opened || mediaContextMenu.opened
  readonly property bool panelCursorVisible: panelCursorActive && !typingInField
    && (!shortcutsBlocked || popupCursorOpen)

  component KeyHint: PanelKeyHint {
    panel: root
  }
  readonly property var panelBar: QtObject {
    readonly property color foreground: root.foreground
    readonly property color background: root.background
    readonly property color urgent: Color.urgent
    readonly property string fontFamily: root.fontFamily
    readonly property string position: "top"
    readonly property bool vertical: false
    readonly property int barSize: 28
  }

  function syncDraftSettings() {
    if (!service) return
    draftDeviceName = service.deviceName
    draftIdleMinutes = String(service.idleShutdownMinutes)
    draftShowMiniPlayer = service.showMiniPlayer
    draftShortcutPlayer = service.shortcutPlayer
    draftShortcutHints = service.shortcutHintsEnabled
    draftShowTitle = service.showTrackTitle
    draftShowArtist = service.showArtistName
    draftShowPausedTrack = service.showPausedTrack
    draftScrollBarText = service.scrollBarText
    draftScrollSpeed = service.scrollSpeed
    draftMaxBarTextWidth = service.maxBarTextWidth
    draftAudioQuality = service.audioQuality
    draftNormalizeVolume = service.normalizeVolume
    draftVolumeLevel = service.volumeLevel
  }

  function saveSettings(showStatus) {
    if (!service) return
    var values = {
      deviceName: String(draftDeviceName || "").trim() || "OmaSpotify",
      idleShutdownMinutes: Math.max(0, Math.min(1440,
        Math.floor(Number(draftIdleMinutes) || 0))),
      showMiniPlayer: draftShowMiniPlayer ? "On" : "Off",
      shortcutPlayer: draftShortcutPlayer,
      shortcutHints: draftShortcutHints ? "On" : "Off",
      showTrackTitle: draftShowTitle ? "On" : "Off",
      showArtistName: draftShowArtist ? "On" : "Off",
      showPausedTrack: draftShowPausedTrack ? "On" : "Off",
      scrollBarText: draftScrollBarText ? "On" : "Off",
      scrollSpeed: Api.normalizedScrollSpeed(draftScrollSpeed),
      maxBarTextWidth: Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth),
      audioQuality: draftAudioQuality,
      normalizeVolume: draftNormalizeVolume ? "On" : "Off",
      volumeLevel: draftVolumeLevel
    }
    service.persistSettings(values)
    syncDraftSettings()
    if (showStatus !== false) service.succeed("Settings saved")
  }

  function persistDraftSettings() {
    saveSettings(false)
  }

  function cycleAudioQuality() {
    draftAudioQuality = draftAudioQuality === "96 kbps" ? "160 kbps"
      : (draftAudioQuality === "160 kbps" ? "320 kbps" : "96 kbps")
    persistDraftSettings()
  }

  function toggleNormalizeVolume() {
    draftNormalizeVolume = !draftNormalizeVolume
    persistDraftSettings()
  }

  function cycleVolumeLevel() {
    draftVolumeLevel = draftVolumeLevel === "Quiet" ? "Normal"
      : (draftVolumeLevel === "Normal" ? "Loud" : "Quiet")
    persistDraftSettings()
  }

  function volumeLevelLabel() {
    return Api.normalizedVolumeLevel(draftVolumeLevel)
  }

  function cycleShortcutPlayer() {
    draftShortcutPlayer = draftShortcutPlayer === "Omarchy Music app"
      ? "Full player"
      : (draftShortcutPlayer === "Full player"
        ? "Mini player" : "Omarchy Music app")
    persistDraftSettings()
  }

  function audioQualityLabel() {
    if (draftAudioQuality === "96 kbps") return "Standard · 96 kbps"
    if (draftAudioQuality === "320 kbps") return "Very high · 320 kbps"
    return "High · 160 kbps"
  }

  function scrollSpeedLabel() {
    var value = Api.normalizedScrollSpeed(draftScrollSpeed)
    return value.toFixed(2).replace(/\.00$/, "").replace(/0$/, "") + "×"
  }

  readonly property var barTextWidthSlider: Api.barTextWidthSlider()
  readonly property bool barTextWidthUnlimited:
    Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth) === 0

  function maxBarTextWidthLabel() {
    var value = Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth)
    return value === 0 ? "Unlimited" : Math.round(value) + " px"
  }
  function maxBarTextWidthSliderValue() {
    var value = Api.normalizedMaxBarTextWidth(draftMaxBarTextWidth)
    return value === 0 ? barTextWidthSlider.unlimited : value
  }
  function setMaxBarTextWidthFromSlider(value) {
    draftMaxBarTextWidth = value >= barTextWidthSlider.unlimited
      ? 0 : Api.normalizedMaxBarTextWidth(value)
    enforceScrollAvailability()
  }

  function enforceScrollAvailability() {
    if (barTextWidthUnlimited) draftScrollBarText = false
    if (!Api.canScrollBarText(draftShowTitle, draftShowArtist))
      draftScrollBarText = false
  }

  function connectionButtonText() {
    if (!service) return "Spotify unavailable"
    if (service.loginBusy) return service.loginProgress + "…"
    if (fullyConnected) return "Connected"
    if (accountConnected && !service.daemon.playbackReady)
      return "Set up playback"
    if (accountConnected) return "Finish playback setup"
    if (!service.daemon.playbackReady) return "Set up and continue"
    return "Continue with Spotify"
  }

  function connectionHeadline() {
    if (!service) return "Spotify is unavailable"
    if (service.daemon.setupBusy) return "Setting up playback"
    if (fullyConnected) return "You're connected"
    if (accountConnected) return "Account connected"
    if (!service.daemon.playbackReady) return "One quick setup, then Spotify"
    return "Continue with Spotify"
  }

  function connectionErrorText() {
    if (!service) return "OmaSpotify is unavailable"
    return service.lastError || service.auth.lastError || service.daemon.lastError
  }

  function playbackStatusText() {
    if (!service) return "Playback is unavailable"
    if (!service.daemon.requirementsChecked) return "Checking playback support…"
    if (service.daemon.setupBusy) return "Preparing playback on this computer…"
    if (!service.daemon.playbackReady) return "A quick one-time setup is needed"
    if (!service.daemon.credentialsChecked) return "Checking your Spotify connection…"
    if (!service.daemon.credentialsAvailable) return "Ready for Spotify sign-in"
    if (service.daemon.running) return "Active on this computer"
    return "Ready — starts automatically when you play music"
  }

  function openMediaContext(item, sceneX, sceneY, sourceItems, contextUri, index,
      playbackContextUri) {
    if (!item) return
    contextItem = item
    contextSourceItems = Array.isArray(sourceItems) ? sourceItems : []
    contextSourceUri = String(contextUri || "")
    contextPlaybackUri = playbackContextUri === undefined
      ? contextSourceUri : String(playbackContextUri || "")
    contextSourceIndex = index === undefined ? -1 : Math.floor(Number(index))
    contextPlaylist = playlistForContext(contextSourceUri)
    mediaContextMenu.x = Math.max(Style.space(6), Math.min(
      window.width - mediaContextMenu.width - Style.space(6), Number(sceneX) || 0))
    mediaContextMenu.y = Math.max(Style.space(6), Math.min(
      window.height - mediaContextMenu.height - Style.space(6), Number(sceneY) || 0))
    mediaContextMenu.open()
  }

  function dismissTransientPopup() {
    if (lyricsInstallPopup.opened && (!service || !service.lyricsPluginBusy)) {
      lyricsInstallPopup.close()
      return true
    }
    if (shortcutHelpPopup.opened) {
      shortcutHelpPopup.close()
      return true
    }
    if (mediaContextMenu.opened) {
      mediaContextMenu.close()
      return true
    }
    if (playlistPicker.opened) {
      playlistPicker.close()
      return true
    }
    if (createPlaylistPopup.opened) {
      createPlaylistPopup.close()
      return true
    }
    if (sleepPopup.opened) {
      sleepPopup.close()
      return true
    }
    return false
  }

  function disarmEscapeClose() {
    escapeCloseTimer.stop()
    escapeCloseArmed = false
  }

  function armEscapeClose() {
    escapeCloseArmed = true
    escapeCloseTimer.restart()
  }

  function releaseSearchFocus() {
    if (unifiedSearchField.activeFocus) unifiedSearchField.focus = false
    focusScope.forceActiveFocus()
  }

  function dismissSearch() {
    var action = Api.searchEscapeAction(unifiedSearchBar.visible,
      unifiedSearchField.activeFocus, unifiedSearchText(),
      showingUniversalSearch && currentTab !== "search")
    if (action === "dismiss") {
      clearUnifiedSearch()
      releaseSearchFocus()
      disarmEscapeClose()
      return true
    }
    if (action === "blur") {
      releaseSearchFocus()
      return false
    }
    return false
  }

  function turnPlaylistIntoOwn(playlist) {
    if (!service || !playlist) return
    service.makePlaylistYourOwn(playlist, function(copy) {
      if (!copy) return
      root.chooseTab("playlists")
      root.service.openPlaylist(copy)
    })
  }

  function playlistForContext(uri) {
    var value = String(uri || "")
    if (!service || !value) return null
    if (service.selectedPlaylist && service.selectedPlaylist.uri === value)
      return service.selectedPlaylist
    if (service.detailItem && service.detailItem.type === "playlist"
        && service.detailItem.uri === value) return service.detailItem
    return null
  }

  function rememberScroll(key, value) {
    var name = String(key || currentTab)
    var position = Math.max(0, Number(value) || 0)
    if (!scrollPositions || typeof scrollPositions !== "object")
      scrollPositions = ({})
    if (!Array.isArray(scrollPositionOrder)) scrollPositionOrder = []
    scrollPositions[name] = position
    var evicted = Api.touchBoundedOrder(scrollPositionOrder, name,
      scrollPositionLimit)
    if (evicted) delete scrollPositions[evicted]
  }

  function scrollFor(key) {
    return Math.max(0, Number(scrollPositions[String(key || currentTab)]) || 0)
  }

  function restoreScrollPositions(values) {
    var source = values && typeof values === "object" ? values : ({})
    var keys = Object.keys(source)
    var start = Math.max(0, keys.length - scrollPositionLimit)
    var next = ({})
    var order = []
    for (var i = start; i < keys.length; i++) {
      var name = keys[i]
      next[name] = Math.max(0, Number(source[name]) || 0)
      order.push(name)
    }
    scrollPositions = next
    scrollPositionOrder = order
  }

  function restoreUiState(restoreDetail) {
    if (!service) return
    var state = service.sessionState || ({})
    service.restoreLastRadioPlaylist(state.lastRadioPlaylist)
    searchText = String(state.searchText || service.searchQuery || "")
    searchType = Api.SEARCH_TYPES.indexOf(String(state.searchType || "")) >= 0
      ? String(state.searchType) : "track"
    libraryType = ["tracks", "albums", "artists", "shows", "episodes", "audiobooks"]
      .indexOf(String(state.libraryType || "")) >= 0 ? String(state.libraryType) : "tracks"
    homeType = ["recent", "tracks", "artists"].indexOf(String(state.homeType || "")) >= 0
      ? String(state.homeType) : "recent"
    libraryFilter = String(state.libraryFilter || "")
    librarySort = String(state.librarySort || "default")
    playlistFilter = String(state.playlistFilter || "")
    playlistSort = String(state.playlistSort || "default")
    detailFilter = String(state.detailFilter || "")
    detailSort = String(state.detailSort || "default")
    homeFilter = String(state.homeFilter || "")
    discoverFilter = String(state.discoverFilter || "")
    queueFilter = String(state.queueFilter || "")
    artistSearchText = String(state.artistSearchText || "")
    searchInContext = true
    universalSearchActive = false
    restoreScrollPositions(state.scrollPositions)
    restoredPlaylist = state.selectedPlaylist && state.selectedPlaylist.id
      && state.selectedPlaylist.type === "playlist" ? state.selectedPlaylist : null
    restoredPlaylistId = String(state.selectedPlaylistId
      || (restoredPlaylist ? restoredPlaylist.id : ""))
    restoredPlaylistItemCount = Api.normalizedPlaylistRestoreCount(
      state.selectedPlaylistItemCount)
    restoredDetailItemCount = Api.normalizedPlaylistRestoreCount(
      state.detailItemCount)
    var restoredTab = String(state.tab || "home")
    if (["home", "discover", "search", "library", "playlists", "detail", "queue", "devices", "setup"]
        .indexOf(restoredTab) >= 0) currentTab = restoredTab
    if (restoreDetail !== false && currentTab === "detail" && state.detailItem) {
      var sameDetail = service.detailItem
        && String(service.detailItem.id) === String(state.detailItem.id)
        && String(service.detailItem.type) === String(state.detailItem.type)
      if (sameDetail) service.ensureDetailItemCount(restoredDetailItemCount)
      else service.openDetail(state.detailItem, artistSearchText,
        restoredDetailItemCount)
    }
    syncUnifiedSearchField()
  }

  function persistUiState() {
    if (!service) return
    var selected = service.selectedPlaylist || restoredPlaylist
    var selectedItemCount = service.selectedPlaylist
      ? service.playlistRememberedItemCount : restoredPlaylistItemCount
    service.persistSession({
      tab: currentTab === "login" ? "home" : currentTab,
      searchText: searchText,
      searchType: searchType,
      libraryType: libraryType,
      homeType: homeType,
      libraryFilter: libraryFilter,
      librarySort: librarySort,
      playlistFilter: playlistFilter,
      playlistSort: playlistSort,
      detailFilter: detailFilter,
      detailSort: detailSort,
      homeFilter: homeFilter,
      discoverFilter: discoverFilter,
      queueFilter: queueFilter,
      artistSearchText: currentTab === "detail" && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : "",
      scrollPositions: scrollPositions,
      detailItem: currentTab === "detail" && service.detailItem ? service.detailItem : null,
      detailItemCount: currentTab === "detail" && service.detailItem
        && service.detailItem.type === "playlist"
        ? service.detailRememberedItemCount : 0,
      selectedPlaylist: selected,
      selectedPlaylistId: selected ? selected.id : restoredPlaylistId,
      selectedPlaylistItemCount: selectedItemCount,
      lastRadioPlaylist: service.lastRadioPlaylist
    })
  }

  function restorePlaylistSelection() {
    if (!service || !restoredPlaylistId || currentTab !== "playlists") return
    if (service.selectedPlaylist) {
      if (String(service.selectedPlaylist.id) === restoredPlaylistId)
        service.ensurePlaylistItemCount(restoredPlaylistItemCount)
      return
    }
    var playlist = service.playlistById(restoredPlaylistId)
    if (!playlist && restoredPlaylist
        && String(restoredPlaylist.id) === restoredPlaylistId)
      playlist = restoredPlaylist
    if (playlist) service.openPlaylist(playlist, restoredPlaylistItemCount)
  }

  function openItem(item) {
    if (!item) return
    if (item.type === "artist" && !item.id) {
      if (service) service.resolveArtist(item.name, function(resolved) {
        root.openItem(resolved)
      })
      return
    }
    if (item.kind !== "context") {
      activateMedia(item, [item], "")
      return
    }
    var stack = navigationStack.slice()
    stack.push({
      tab: currentTab,
      item: currentTab === "detail" && service ? service.detailItem : null,
      universalSearchActive: universalSearchActive,
      searchInContext: searchInContext,
      artistSearchText: currentTab === "detail" && service && service.detailItem
        && service.detailItem.type === "artist" ? artistSearchText : "",
      detailFilter: currentTab === "detail" && service && service.detailItem
        && service.detailItem.type !== "artist" ? detailFilter : ""
    })
    navigationStack = stack
    unifiedSearchDelay.stop()
    searchInContext = true
    universalSearchActive = false
    if (service) service.cancelSearch(false)
    currentTab = "detail"
    if (item.type === "artist") artistSearchText = ""
    else detailFilter = ""
    if (service) service.openDetail(item)
    syncUnifiedSearchField()
  }

  function openCurrentArtist() {
    if (!service || !service.currentArtistContextAvailable) return
    service.currentContext("artist", function(item) { openItem(item) })
  }

  function openCurrentAlbum() {
    if (!service || !service.currentAlbumContextAvailable) return
    service.currentContext("album", function(item) { openItem(item) })
  }

  function goBack() {
    if (!navigationStack.length) {
      chooseTab("home")
      return
    }
    var stack = navigationStack.slice()
    var destination = stack.pop()
    navigationStack = stack
    unifiedSearchDelay.stop()
    if (service) service.cancelSearch(false)
    currentTab = destination.tab || "search"
    universalSearchActive = destination.universalSearchActive === true
    searchInContext = destination.searchInContext === undefined
      ? !universalSearchActive : destination.searchInContext === true
    if (currentTab === "detail" && destination.item && service) {
      artistSearchText = destination.item.type === "artist"
        ? String(destination.artistSearchText || "") : ""
      detailFilter = destination.item.type === "artist"
        ? "" : String(destination.detailFilter || "")
      service.openDetail(destination.item, artistSearchText)
    }
    if (service && (currentTab === "search" || universalSearchActive)) {
      if (searchText.trim() === "") service.clearSearch()
      else service.search(searchText)
    }
    else if (service && currentTab !== "detail") service.openView(currentTab, false)
    syncUnifiedSearchField()
  }

  function activateMedia(item, sourceItems, contextUri, successMessage) {
    if (!item || !service) return
    if (unifiedSearchField.activeFocus) focusScope.forceActiveFocus()
    service.playItem(item, sourceItems, contextUri, successMessage)
  }

  function playSelectedPlaylist() {
    if (!service || !service.selectedPlaylist) return
    var collection = pageCollection()
    if (collection && collection.playbackUsesVisibleOrder) {
      var items = Api.arrayValues(collection.visibleItems)
      if (!items.length) {
        service.fail("No visible playlist items to play")
        return
      }
      activateMedia(items[0], items, "",
        Api.visibleOrderPlaybackMessage(items.length))
      return
    }
    activateMedia(service.selectedPlaylist)
  }

  function textInputFocused() {
    var item = window.activeFocusItem
    return !!item && ("acceptableInput" in item || "echoMode" in item)
  }

  function shortcutHint(label, keys) {
    var text = String(label || "")
    var shortcut = String(keys || "")
    return shortcut ? text + " · " + shortcut : text
  }

  function applySequenceModifiers(sequence) {
    heldModifierFlags = shortcutModifiers.flagsForSequence(sequence)
  }

  function latchShortcutMode(sequence) {
    if (!shortcutHintsEnabled) return
    shortcutModeLatched = true
    if (sequence) applySequenceModifiers(sequence)
    syncCollectionCursor()
  }

  function clearShortcutMode() {
    shortcutModeLatched = false
    heldModifierFlags = 0
    panelCursorActive = false
  }

  function disableShortcutHints() {
    draftShortcutHints = false
    if (service) service.persistSettings({ shortcutHints: "Off" })
    else clearShortcutMode()
  }





  function noteHeldModifiers(event, pressed) {
    if (!event) return
    heldModifierFlags = shortcutModifiers.flagsAfterEvent(event.modifiers,
      pressed, heldModifierFlags, event.key)
  }

  function considerShortcutModeKey(event, pressed) {
    noteHeldModifiers(event, pressed)
    if (!pressed || typingInField) return
    if (shortcutModifiers.isHintModifierKey(event.key) || event.key === Qt.Key_Tab
        || event.key === Qt.Key_Backtab || event.key === Qt.Key_F6
        || (event.modifiers & (Qt.ControlModifier | Qt.ShiftModifier
          | Qt.AltModifier)) !== 0)
      latchShortcutMode()
  }

  function cursorOn(region, action) {
    return panelCursorVisible && panelCursorRegion === region
      && panelCursorAction === action
  }

  function cursorActionsByRegion() {
    return {
      sidebar: sidebarCursorActions(),
      header: headerCursorActions(),
      page: pageCursorActions(),
      footer: footerCursorActions(),
      popup: sleepCursorActions()
    }
  }

  function pageListCount() {
    var collection = pageCollection()
    if (collection) return collection.listCount
    var list = pageListView()
    return list ? list.count : 0
  }

  function firstVisibleIndexOf(list) {
    if (!list || list.count <= 0) return 0
    var y = list.contentY + 1
    if (list.originY !== undefined && y < list.originY) y = list.originY + 1
    var index = list.indexAt(Math.max(1, list.width / 2), y)
    return Api.listHintRowIndex(list.count, index)
  }

  function tabDestination(back) {
    if (unifiedSearchField.activeFocus) {
      return Api.tabCursorDestination({
        regions: panelCursorRegions(),
        currentRegion: "header",
        currentAction: "search",
        pageActions: pageCursorActions(),
        actionsByRegion: cursorActionsByRegion(),
        listCount: pageListCount(),
        pageLanding: searchPageLanding(),
        cursorActive: true,
        back: !!back
      })
    }
    if (sleepPopup.opened) {
      return Api.tabCursorDestination({
        regions: ["popup"],
        currentRegion: "popup",
        currentAction: panelCursorAction,
        actionsByRegion: cursorActionsByRegion(),
        cursorActive: true,
        back: !!back
      })
    }
    return Api.tabCursorDestination({
      regions: panelCursorRegions(),
      currentRegion: panelCursorRegion,
      currentAction: panelCursorAction,
      pageActions: pageCursorActions(),
      actionsByRegion: cursorActionsByRegion(),
      listCount: pageListCount(),
      pageLanding: searchPageLanding(),
      cursorActive: panelCursorActive,
      back: !!back
    })
  }

  function jumpToListTabRow() {
    var collection = collectionForListAction(panelCursorAction)
    if (collection && collection.jumpToFirstVisible) {
      collection.jumpToFirstVisible()
      return
    }
    var list = pageListView()
    if (!list || list.count <= 0) return
    var index = firstVisibleIndexOf(list)
    if (index >= 0) list.currentIndex = index
  }

  function searchPageLanding() {
    if (!showingUniversalSearch) return ""
    var type = String(searchType || "track")
    return "search-" + type
  }

  function applyCursorDestination(dest) {
    if (!dest || !dest.region) return
    latchShortcutMode()
    panelCursorActive = true
    var fromRegion = panelCursorRegion
    var fromAction = panelCursorAction
    panelCursorRegion = dest.region
    panelCursorAction = dest.action
    ensurePanelCursor(dest.region)
    if (dest.action && regionCursorActions(panelCursorRegion).indexOf(dest.action) >= 0)
      panelCursorAction = dest.action
    if (Api.isCursorListAction(panelCursorAction)
        && (fromRegion !== "page" || fromAction !== panelCursorAction))
      jumpToListTabRow()
    syncCursorFocus()
  }

  function applyTabDestination(back) {
    applyCursorDestination(tabDestination(back))
  }

  function navHintFor(region, action) {
    if (!shortcutHintsEnabled || !shortcutModeLatched) return ""
    var tab = tabDestination(false)
    var back = tabDestination(true)
    var listAction = ""
    var listIndex = -1
    var listCount = 0
    if (region === "sidebar") {
      listAction = "sidebar-playlists"
      listIndex = playlistShortcuts.currentIndex
      listCount = playlistShortcuts.count
    } else if (region === "page") {
      listAction = Api.isCursorListAction(panelCursorAction)
        ? panelCursorAction : ""
      var collection = collectionForListAction(listAction || "list")
      var list = pageListView()
      if (collection) {
        listIndex = collection.listCurrentIndex
        listCount = collection.listCount
      } else if (list) {
        listIndex = list.currentIndex
        listCount = list.count
      }
    }
    return Api.cursorNavHint({
      region: region,
      action: action,
      currentRegion: panelCursorRegion,
      currentAction: panelCursorAction,
      regionActions: regionCursorActions(panelCursorRegion),
      tabRegion: tab.region,
      tabAction: tab.action,
      backtabRegion: back.region,
      backtabAction: back.action,
      listAction: listAction,
      listIndex: listIndex,
      listCount: listCount,
      cursorActive: panelCursorVisible,
      modifiersHeld: hintCtrlHeld || hintShiftHeld || hintAltHeld
    })
  }

  function pageListRowHint(index, list) {
    if (!list || !panelCursorVisible || !shortcutHintsActive) return ""
    var actions = pageCursorActions()
    var prev = Api.moveCursorAction(actions, "list", -1)
    var next = Api.moveCursorAction(actions, "list", 1)
    var tab = tabDestination(false)
    var back = tabDestination(true)
    return Api.cursorListRowHint({
      rowIndex: index,
      currentIndex: list.currentIndex,
      count: list.count,
      tabRowIndex: firstVisibleIndexOf(list),
      atList: panelCursorRegion === "page" && panelCursorAction === "list",
      previousIsCurrent: panelCursorRegion === "page" && panelCursorAction === prev
        && prev !== "list",
      nextIsCurrent: panelCursorRegion === "page" && panelCursorAction === next
        && next !== "list",
      tabIsList: tab.region === "page" && tab.action === "list",
      backtabIsList: back.region === "page" && back.action === "list",
      modifiersHeld: hintCtrlHeld || hintShiftHeld || hintAltHeld
    })
  }

  function sidebarPlaylistNavHint(index) {
    if (!panelCursorVisible || !shortcutHintsActive) return ""
    var actions = sidebarCursorActions()
    var prev = Api.moveCursorAction(actions, "sidebar-playlists", -1)
    var next = Api.moveCursorAction(actions, "sidebar-playlists", 1)
    var tab = tabDestination(false)
    var back = tabDestination(true)
    return Api.cursorListRowHint({
      rowIndex: index,
      currentIndex: playlistShortcuts.currentIndex,
      count: playlistShortcuts.count,
      tabRowIndex: firstVisibleIndexOf(playlistShortcuts),
      atList: panelCursorRegion === "sidebar"
        && panelCursorAction === "sidebar-playlists",
      previousIsCurrent: panelCursorRegion === "sidebar"
        && panelCursorAction === prev && prev !== "sidebar-playlists",
      nextIsCurrent: panelCursorRegion === "sidebar"
        && panelCursorAction === next && next !== "sidebar-playlists",
      tabIsList: tab.region === "sidebar" && tab.action === "sidebar-playlists",
      backtabIsList: back.region === "sidebar"
        && back.action === "sidebar-playlists",
      modifiersHeld: hintCtrlHeld || hintShiftHeld || hintAltHeld
    })
  }

  function findNamedItem(item, name) {
    if (!item) return null
    if (item.visible === false) return null
    if (item.objectName === name) return item
    var kids = item.children
    if (!kids) return null
    for (var i = 0; i < kids.length; i++) {
      var found = findNamedItem(kids[i], name)
      if (found) return found
    }
    return null
  }

  function findNamedItems(item, name, found) {
    var results = found || []
    if (!item || item.visible === false) return results
    if (item.objectName === name) results.push(item)
    var kids = item.children
    if (!kids) return results
    for (var i = 0; i < kids.length; i++)
      findNamedItems(kids[i], name, results)
    return results
  }

  function pageCollection() {
    return findNamedItem(pageLoader.item, "media-collection")
  }

  function pageCollections() {
    return findNamedItems(pageLoader.item, "media-collection")
  }

  function pageListView() {
    return findNamedItem(pageLoader.item, "page-list")
  }

  function collectionForListAction(action) {
    var id = String(action || "list")
    var collections = pageCollections()
    for (var i = 0; i < collections.length; i++) {
      var collection = collections[i]
      var listId = collection.keyboardListId || "list"
      if (listId === id) return collection
    }
    if (id === "list" && collections.length) return collections[0]
    return null
  }

  function sidebarCursorActions() {
    if (currentTab === "login") return []
    var actions = []
    var items = primaryNavigationItems()
    for (var i = 0; i < items.length; i++)
      actions.push("nav-" + items[i].id)
    actions.push("nav-library", "nav-playlists")
    if (accountConnected && service && !service.playlistActionBusy)
      actions.push("nav-create")
    if (!compactWidth && service && service.sidebarPlaylists().length)
      actions.push("sidebar-playlists")
    actions.push("nav-settings")
    return actions
  }

  function headerCursorActions() {
    var actions = []
    if (backButton.visible) actions.push("back")
    if (unifiedSearchBar.visible) {
      actions.push("search")
      if (searchScopeButton.visible) actions.push("scope")
    }
    actions.push("help")
    if (refreshButton.visible) actions.push("refresh")
    actions.push("close")
    return actions
  }

  function footerCursorActions() {
    if (currentTab === "login") return []
    var actions = []
    if (service && service.currentTrackSaveAvailable) actions.push("like")
    if (service && service.currentTrackItem) actions.push("context")
    if (service && service.currentArtistContextAvailable) actions.push("artist")
    if (service && service.currentAlbumContextAvailable) actions.push("album")
    if (service && service.playbackControllable)
      actions.push("shuffle", "previous", "play", "next", "repeat")
    if (service && service.lyricsAvailable) actions.push("lyrics")
    if (service && service.lengthSeconds > 0 && service.playbackControllable)
      actions.push("seek")
    actions.push("devices", "sleep")
    if (service && service.volumeSupported) actions.push("volume")
    return actions
  }

  function pageCursorActions() {
    var actions = []
    if (currentTab === "home")
      actions.push("home-recent", "home-tracks", "home-artists")
    if (currentTab === "library")
      actions.push("library-tracks", "library-albums", "library-artists",
        "library-shows", "library-episodes", "library-audiobooks")
    if (currentTab === "playlists" && service && service.selectedPlaylist)
      actions.push("playlist-play", "playlist-more")
    if (showingUniversalSearch) {
      for (var s = 0; s < Api.SEARCH_TYPES.length; s++)
        actions.push("search-" + Api.SEARCH_TYPES[s])
    }
    var artistCatalog = currentTab === "detail" && service && service.detailItem
      && service.detailItem.type === "artist" && !artistScopedSearchActive
      && !showingUniversalSearch
    if (currentTab === "detail" && service && service.detailItem
        && !showingUniversalSearch) {
      var kind = service.detailItem.type
      if (["show", "audiobook"].indexOf(kind) < 0
          || (service.detailItems && service.detailItems.length > 0))
        actions.push("detail-play")
      actions.push("detail-save", "detail-more")
    }
    if (artistCatalog) {
      actions.push("list-albums", "list-songs")
      if (service && service.artistThisIsPlaylist) actions.push("detail-thisis")
    } else {
      var collection = pageCollection()
      if (collection && collection.showSort) actions.push("sort")
      if (collection || pageListView()) actions.push("list")
      if (collection && collection.hasMore) actions.push("more")
    }
    return actions
  }

  function sleepCursorActions() {
    var actions = ["sleep-15", "sleep-30", "sleep-60", "sleep-120",
      "sleep-track", "sleep-context"]
    if (service && service.sleepActive) actions.push("sleep-cancel")
    return actions
  }

  function panelCursorRegions() {
    var regions = []
    if (sidebarCursorActions().length) regions.push("sidebar")
    regions.push("header")
    if (pageCursorActions().length) regions.push("page")
    if (footerCursorActions().length) regions.push("footer")
    return regions
  }

  function regionCursorActions(region) {
    if (region === "sidebar") return sidebarCursorActions()
    if (region === "header") return headerCursorActions()
    if (region === "page") return pageCursorActions()
    if (region === "footer") return footerCursorActions()
    if (region === "popup") {
      if (mediaContextMenu.opened) return contextMenuCursorActions()
      return sleepCursorActions()
    }
    return []
  }

  function ensurePanelCursor(preferredRegion) {
    var region = preferredRegion || panelCursorRegion
    if (popupCursorOpen) region = "popup"
    var regions = panelCursorRegions()
    if (popupCursorOpen) regions = ["popup"]
    region = Api.ensureCursorAction(regions, region,
      preferredRegion || "footer")
    panelCursorRegion = region
    var fallback = region === "footer" ? "play" : ""
    panelCursorAction = Api.ensureCursorAction(regionCursorActions(region),
      panelCursorAction, fallback)
    syncCollectionCursor()
  }

  function setPanelCursor(region, action) {
    panelCursorActive = true
    panelCursorRegion = region
    panelCursorAction = action
    ensurePanelCursor(region)
    syncCursorFocus()
  }

  function movePanelCursorRegion(delta) {
    latchShortcutMode()
    panelCursorActive = true
    var regions = panelCursorRegions()
    panelCursorRegion = Api.moveCursorAction(regions, panelCursorRegion, delta)
    ensurePanelCursor(panelCursorRegion)
    syncCursorFocus()
  }

  function moveSidebarPlaylists(delta) {
    var count = playlistShortcuts.count
    var next = Api.listIndexAfterMove(count, playlistShortcuts.currentIndex, delta)
    if (next < 0) return false
    playlistShortcuts.currentIndex = next
    return true
  }

  function movePageList(delta) {
    var collection = collectionForListAction(panelCursorAction)
    if (collection && collection.moveCurrent) return collection.moveCurrent(delta)
    var list = pageListView()
    if (!list) return false
    var next = Api.listIndexAfterMove(list.count, list.currentIndex, delta)
    if (next < 0) return false
    list.currentIndex = next
    return true
  }

  function enterListAction(action, delta) {
    if (action === "sidebar-playlists" && playlistShortcuts.count > 0) {
      playlistShortcuts.currentIndex = delta < 0
        ? playlistShortcuts.count - 1 : 0
      return
    }
    if (!Api.isCursorListAction(action)) return
    var collection = collectionForListAction(action)
    if (collection && collection.jumpToEdge) {
      collection.jumpToEdge(delta < 0)
      return
    }
    var list = pageListView()
    if (list && list.count > 0)
      list.currentIndex = delta < 0 ? list.count - 1 : 0
  }

  function movePanelCursor(delta) {
    latchShortcutMode()
    panelCursorActive = true
    ensurePanelCursor()
    var from = panelCursorAction
    var to = Api.moveCursorAction(
      regionCursorActions(panelCursorRegion), panelCursorAction, delta)
    if (from !== to) enterListAction(to, delta)
    panelCursorAction = to
    ensurePanelCursor()
    syncCursorFocus()
  }

  function blurPageLists() {
    var collections = pageCollections()
    for (var i = 0; i < collections.length; i++) {
      if (collections[i] && collections[i].blurList) collections[i].blurList()
    }
    var list = pageListView()
    if (list && list.activeFocus) list.focus = false
  }

  function syncCursorFocus() {
    if (!panelCursorActive || typingInField) return
    if (panelCursorAction === "sidebar-playlists") {
      if (playlistShortcuts.currentIndex < 0 && playlistShortcuts.count > 0)
        playlistShortcuts.currentIndex = 0
      blurPageLists()
      focusScope.forceActiveFocus()
      return
    }
    if (Api.isCursorListAction(panelCursorAction)) {
      var collection = collectionForListAction(panelCursorAction)
      if (collection && collection.focusList) collection.focusList()
      else if (pageListView()) {
        var list = pageListView()
        list.forceActiveFocus()
        if (list.currentIndex < 0 && list.count > 0) list.currentIndex = 0
      }
      return
    }
    blurPageLists()
    focusScope.forceActiveFocus()
  }

  function syncCollectionCursor() {
    var collections = pageCollections()
    var actions = pageCursorActions()
    var tab = tabDestination(false)
    var back = tabDestination(true)
    var hintsOn = shortcutHintsActive
    for (var i = 0; i < collections.length; i++) {
      var collection = collections[i]
      var id = collection.keyboardListId || "list"
      var prev = Api.moveCursorAction(actions, id, -1)
      var next = Api.moveCursorAction(actions, id, 1)
      collection.keyboardHintsActive = hintsOn
      collection.keyboardSortSelected = cursorOn("page", "sort")
      collection.keyboardMoreSelected = cursorOn("page", "more")
      collection.keyboardSortHint = hintsOn ? navHintFor("page", "sort") : ""
      collection.keyboardMoreHint = hintsOn ? navHintFor("page", "more") : ""
      collection.keyboardListHint = ""
      collection.keyboardAtList = cursorOn("page", id)
      collection.keyboardAtListPrev = cursorOn("page", prev)
        && !Api.isCursorListAction(prev)
      collection.keyboardAtListNext = cursorOn("page", next)
        && !Api.isCursorListAction(next)
      collection.keyboardListIsTab = hintsOn && tab.region === "page"
        && tab.action === id
      collection.keyboardListIsBacktab = hintsOn && back.region === "page"
        && back.action === id
      collection.keyboardNavModifiers = hintCtrlHeld || hintShiftHeld
        || hintAltHeld
      collection.keyboardCtrlHeld = hintCtrlHeld
      collection.keyboardShiftHeld = hintShiftHeld
      collection.keyboardAltHeld = hintAltHeld
    }
  }

  function activatePanelCursor() {
    latchShortcutMode()
    panelCursorActive = true
    ensurePanelCursor()
    var action = panelCursorAction
    if (action === "nav-home") chooseTab("home")
    else if (action === "nav-discover") chooseTab("discover")
    else if (action === "nav-radio") openLastRadio()
    else if (action === "nav-queue") chooseTab("queue")
    else if (action === "nav-library") chooseTab("library")
    else if (action === "nav-playlists") chooseTab("playlists")
    else if (action === "nav-create") openCreatePlaylistPopup()
    else if (action === "sidebar-playlists") {
      var playlists = service ? service.sidebarPlaylists() : []
      var playlist = playlists[playlistShortcuts.currentIndex]
      if (playlist) {
        chooseTab("playlists")
        service.openPlaylist(playlist)
      }
    } else if (action === "nav-settings") chooseTab("setup")
    else if (action === "back") goBack()
    else if (action === "search") focusSearch()
    else if (action === "scope") toggleSearchScope()
    else if (action === "help") toggleShortcutHelp()
    else if (action === "refresh") refreshButton.clicked()
    else if (action === "close") requestClose()
    else if (action === "like" && service) service.toggleCurrentTrackSaved()
    else if (action === "context") openNowPlayingContext()
    else if (action === "artist") openCurrentArtist()
    else if (action === "album") openCurrentAlbum()
    else if (action === "shuffle" && service)
      service.setShuffle(!service.shuffle)
    else if (action === "previous" && service) service.previous()
    else if (action === "play" && service) service.togglePlayback()
    else if (action === "next" && service) service.next()
    else if (action === "repeat" && service) service.cycleRepeat()
    else if (action === "lyrics") openLyrics()
    else if (action === "devices") chooseTab("devices")
    else if (action === "sleep") sleepPopup.open()
    else if (action === "volume") toggleMute()
    else if (action.indexOf("home-") === 0) homeType = action.substring(5)
    else if (action.indexOf("library-") === 0) {
      libraryType = action.substring(8)
      if (service) service.loadLibrary(libraryType, false)
    } else if (action.indexOf("search-") === 0) {
      searchType = action.substring(7)
    } else if (action === "playlist-play" && service && service.selectedPlaylist)
      playSelectedPlaylist()
    else if (action === "playlist-more" && service && service.selectedPlaylist)
      openMediaContext(service.selectedPlaylist, Style.space(80),
        Style.space(120), [], service.selectedPlaylist.uri, -1)
    else if (action === "sort") {
      var sortCollection = pageCollection()
      if (sortCollection) sortCollection.cycleSort()
    } else if (action === "detail-play" && service && service.detailItem) {
      if (["show", "audiobook"].indexOf(service.detailItem.type) >= 0
          && service.detailItems && service.detailItems.length)
        activateMedia(service.detailItems[0], service.detailItems, "")
      else activateMedia(service.detailItem)
    } else if (action === "detail-save" && service && service.detailItem) {
      if (!service.isSaved(service.detailItem))
        service.toggleSaved(service.detailItem)
    } else if (action === "detail-more" && service && service.detailItem) {
      openMediaContext(service.detailItem, Style.space(80), Style.space(120),
        service.detailItems || [], service.detailItem.uri, -1)
    } else if (action === "detail-thisis") {
      var thisIs = findNamedItem(pageLoader.item, "artist-thisis")
      if (thisIs && thisIs.triggerPrimary) thisIs.triggerPrimary()
    } else if (String(action).indexOf("ctx-") === 0) {
      activateContextMenuAction(action)
    } else if (Api.isCursorListAction(action)) {
      var current = collectionForListAction(action)
      if (current && current.activateCurrent) current.activateCurrent()
      else {
        var list = pageListView()
        if (list && list.currentItem && list.currentItem.triggerPrimary)
          list.currentItem.triggerPrimary()
      }
    } else if (action === "more") {
      var more = pageCollection()
      if (more && more.requestMore) more.requestMore()
    } else if (action === "sleep-15" && service) {
      service.setSleepMinutes(15)
      sleepPopup.close()
    } else if (action === "sleep-30" && service) {
      service.setSleepMinutes(30)
      sleepPopup.close()
    } else if (action === "sleep-60" && service) {
      service.setSleepMinutes(60)
      sleepPopup.close()
    } else if (action === "sleep-120" && service) {
      service.setSleepMinutes(120)
      sleepPopup.close()
    } else if (action === "sleep-track" && service) {
      service.sleepAfterTrack()
      sleepPopup.close()
    } else if (action === "sleep-context" && service) {
      service.sleepAfterContext()
      sleepPopup.close()
    } else if (action === "sleep-cancel" && service) {
      service.cancelSleepTimer(true)
      sleepPopup.close()
    }
  }

  function openPanelListContext() {
    var action = Api.isCursorListAction(panelCursorAction)
      ? panelCursorAction : "list"
    var collection = collectionForListAction(action)
    if (collection && collection.currentContextAnchor) {
      if (collection.listCurrentIndex < 0 && collection.focusList)
        collection.focusList()
      var anchor = collection.currentContextAnchor()
      if (anchor && anchor.item) {
        openMediaContext(anchor.item, anchor.x, anchor.y, anchor.items,
          anchor.uri, anchor.index, anchor.playbackUri)
        return true
      }
    }
    var list = pageListView()
    if (list && list.count > 0) {
      if (list.currentIndex < 0) list.currentIndex = 0
      if (list.currentItem && list.currentItem.itemData) {
        var row = list.currentItem
        var point = row.mapToItem(null, row.width / 2, row.height / 2)
        openMediaContext(row.itemData, point.x, point.y,
          list.model || [], "", list.currentIndex)
        return true
      }
    }
    return false
  }

  function nowPlayingContextItem() {
    if (!service || !service.currentTrackItem) return null
    var item = Api.shallowCopy(service.currentTrackItem)
    if (service.currentArtists.length) item.artists = service.currentArtists
    if (service.currentAlbumItem) item.albumItem = service.currentAlbumItem
    return item
  }

  function openNowPlayingContext() {
    var item = nowPlayingContextItem()
    if (!item) return false
    var x = Style.space(80)
    var y = Math.max(Style.space(8), window.height - Style.space(160))
    var anchor = currentTrackMoreButton.visible ? currentTrackMoreButton
      : currentTrackLikeButton
    if (anchor && anchor.visible) {
      var point = anchor.mapToItem(window.contentItem, anchor.width, 0)
      x = point.x
      y = point.y
    }
    openMediaContext(item, x, y, [item], item.uri, 0)
    return true
  }

  function openCurrentContextMenu() {
    if (panelCursorAction === "playlist-more"
        || panelCursorAction === "detail-more") {
      activatePanelCursor()
      return mediaContextMenu.opened
    }
    if (panelCursorRegion === "page"
        || Api.isCursorListAction(panelCursorAction)) {
      if (openPanelListContext()) return true
    }
    return openNowPlayingContext()
  }

  function contextMenuButtons() {
    var result = []
    var kids = mediaContextMenu.actionButtons()
    for (var i = 0; i < kids.length; i++) {
      var child = kids[i]
      var action = child && child.contextAction ? String(child.contextAction) : ""
      if (!action || child.visible === false || child.enabled === false) continue
      result.push(child)
    }
    return result
  }

  function contextMenuCursorActions() {
    var buttons = contextMenuButtons()
    var actions = []
    for (var i = 0; i < buttons.length; i++)
      actions.push(buttons[i].contextAction)
    return actions
  }

  function activateContextMenuAction(action) {
    var buttons = contextMenuButtons()
    for (var i = 0; i < buttons.length; i++) {
      if (buttons[i].contextAction === action) {
        buttons[i].clicked()
        return true
      }
    }
    return false
  }

  function contextMenuMoveDelta(event) {
    if (!event) return 0
    var key = event.key
    var text = String(event.text || "").toLowerCase()
    if (key === Qt.Key_Up || key === Qt.Key_K || key === Qt.Key_Left
        || key === Qt.Key_H || text === "k" || text === "h")
      return -1
    if (key === Qt.Key_Down || key === Qt.Key_J || key === Qt.Key_Right
        || key === Qt.Key_L || text === "j" || text === "l")
      return 1
    return 0
  }

  function moveContextMenuCursor(delta) {
    if (!mediaContextMenu.opened || !delta) return false
    latchShortcutMode()
    panelCursorActive = true
    panelCursorRegion = "popup"
    panelCursorAction = Api.moveCursorAction(contextMenuCursorActions(),
      panelCursorAction, delta)
    ensurePanelCursor("popup")
    return true
  }

  function handleContextMenuKey(event) {
    if (!mediaContextMenu.opened || !event) return false
    var key = event.key
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var tabbing = key === Qt.Key_Tab || key === Qt.Key_Backtab
      || key === Qt.Key_F6
    var move = contextMenuMoveDelta(event)
    if (tabbing) {
      latchShortcutMode()
      panelCursorActive = true
      panelCursorRegion = "popup"
      panelCursorAction = Api.moveCursorAction(contextMenuCursorActions(),
        panelCursorAction, (shift || key === Qt.Key_Backtab) ? -1 : 1)
      ensurePanelCursor("popup")
      return true
    }
    if (move) return moveContextMenuCursor(move)
    if (key === Qt.Key_Return || key === Qt.Key_Enter) {
      latchShortcutMode()
      activatePanelCursor()
      return true
    }
    if (key === Qt.Key_Home || key === Qt.Key_End) {
      latchShortcutMode()
      panelCursorActive = true
      panelCursorRegion = "popup"
      var actions = contextMenuCursorActions()
      if (actions.length) {
        panelCursorAction = key === Qt.Key_Home
          ? actions[0] : actions[actions.length - 1]
        ensurePanelCursor("popup")
      }
      return true
    }
    return false
  }

  function handlePanelCursorKey(event) {
    if (!event) return false
    var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
    var shift = (event.modifiers & Qt.ShiftModifier) !== 0
    var alt = (event.modifiers & Qt.AltModifier) !== 0
    var key = event.key
    var text = String(event.text || "").toLowerCase()
    var tabbing = key === Qt.Key_Tab || key === Qt.Key_Backtab
      || key === Qt.Key_F6
    var menuKey = key === Qt.Key_Menu || (shift && key === Qt.Key_F10)
      || (!ctrl && !shift && !alt && (key === Qt.Key_C || text === "c"))

    if (mediaContextMenu.opened)
      return handleContextMenuKey(event)

    if (createPlaylistPopup.opened || playlistPicker.opened
        || shortcutHelpPopup.opened || lyricsInstallPopup.opened)
      return false

    if (unifiedSearchField.activeFocus && tabbing) {
      var searchDest = tabDestination(shift || key === Qt.Key_Backtab)
      releaseSearchFocus()
      applyCursorDestination(searchDest)
      return true
    }

    if (typingInField) return false

    if (ctrl && !shift && !alt && (key === Qt.Key_Up || key === Qt.Key_Down)
        && service && service.volumeSupported) {
      latchShortcutMode(key === Qt.Key_Up ? "Ctrl+Up" : "Ctrl+Down")
      adjustVolume(key === Qt.Key_Up ? 0.05 : -0.05)
      return true
    }

    if (sleepPopup.opened) {
      if (tabbing) {
        applyTabDestination(shift || key === Qt.Key_Backtab)
        return true
      }
      if (key === Qt.Key_Down || key === Qt.Key_Up
          || text === "j" || text === "k" || key === Qt.Key_Left
          || key === Qt.Key_Right || text === "h" || text === "l") {
        latchShortcutMode()
        panelCursorActive = true
        panelCursorRegion = "popup"
        var sleepDelta = (key === Qt.Key_Up
          || text === "k" || key === Qt.Key_Left || text === "h") ? -1 : 1
        panelCursorAction = Api.moveCursorAction(sleepCursorActions(),
          panelCursorAction, sleepDelta)
        ensurePanelCursor("popup")
        return true
      }
      if (key === Qt.Key_Return || key === Qt.Key_Enter) {
        activatePanelCursor()
        return true
      }
      return false
    }

    if (tabbing) {
      latchShortcutMode()
      if (!panelCursorActive) {
        panelCursorActive = true
        ensurePanelCursor("footer")
        syncCursorFocus()
        return true
      }
      applyTabDestination(shift || key === Qt.Key_Backtab)
      return true
    }

    var vertical = key === Qt.Key_Up || key === Qt.Key_Down || text === "k"
      || text === "j"
    var horizontal = key === Qt.Key_Left || key === Qt.Key_Right
      || text === "h" || text === "l"
    var delta = (key === Qt.Key_Up || text === "k" || key === Qt.Key_Left
      || text === "h") ? -1 : 1

    if (!ctrl && !alt && !(shift && (key === Qt.Key_Left || key === Qt.Key_Right
          || key === Qt.Key_Up || key === Qt.Key_Down))
        && (vertical || horizontal) && (panelCursorActive
        || key === Qt.Key_Up || key === Qt.Key_Down || key === Qt.Key_Left
        || key === Qt.Key_Right)) {
      latchShortcutMode()
      panelCursorActive = true
      ensurePanelCursor()
      if (!ctrl && !alt && (panelCursorAction === "seek"
          || panelCursorAction === "volume") && horizontal) {
        if (panelCursorAction === "seek") seekBy(delta * 5)
        else adjustVolume(delta * 0.05)
        return true
      }
      if (vertical && panelCursorAction === "sidebar-playlists"
          && moveSidebarPlaylists(delta))
        return true
      if (vertical && Api.isCursorListAction(panelCursorAction)
          && movePageList(delta)) {
        syncCollectionCursor()
        return true
      }
      movePanelCursor(delta)
      return true
    }

    if (panelCursorActive && (key === Qt.Key_Return || key === Qt.Key_Enter)) {
      activatePanelCursor()
      return true
    }
    if (menuKey && openCurrentContextMenu()) {
      latchShortcutMode()
      return true
    }
    if (panelCursorActive && !ctrl && !alt && !shift
        && (key === Qt.Key_Home || key === Qt.Key_End)) {
      var actions = regionCursorActions(panelCursorRegion)
      if (actions.length) {
        panelCursorAction = key === Qt.Key_Home
          ? actions[0] : actions[actions.length - 1]
        syncCursorFocus()
      }
      return true
    }
    return false
  }

  function primaryNavigationShortcut(id) {
    if (id === "home") return "Alt+Shift+H"
    if (id === "queue") return "Alt+Shift+Q"
    return ""
  }

  function shortcutRows() {
    return [
      { section: "SEARCH", action: "Focus search", keys: "Ctrl+F or /" },
      { action: "Toggle this area / all of Spotify", keys: "Ctrl+F or /" },
      { action: "Leave search", keys: "Esc" },
      { section: "NAVIGATION", action: "Go back", keys: "Alt+Left" },
      { action: "Leave Settings or Devices", keys: "Esc" },
      { action: "Open Settings", keys: "Ctrl+," },
      { action: "Open For You", keys: "Alt+Shift+H" },
      { action: "Open Queue", keys: "Alt+Shift+Q" },
      { action: "Open Devices", keys: "Alt+Shift+D" },
      { action: "Open the current artist", keys: "Ctrl+Shift+A" },
      { action: "Open the current album", keys: "Ctrl+Shift+B" },
      { action: "Move between sidebar, search, the song list, and the player", keys: "Tab / F6" },
      { action: "Move to a control", keys: "Arrow keys" },
      { action: "Activate the highlighted control", keys: "Enter" },
      { action: "Row actions", keys: "C" },
      { action: "Choose a row action", keys: "Arrow keys or Enter" },
      { action: "Move through lists", keys: "Arrow keys" },
      { action: "Open the selected item", keys: "Enter" },
      { section: "PLAYBACK", action: "Play or pause", keys: "Space" },
      { action: "Previous track", keys: "Ctrl+Left" },
      { action: "Next track", keys: "Ctrl+Right" },
      { action: "Open lyrics in Omasing", keys: "Ctrl+Shift+L" },
      { action: "Mute or restore volume", keys: "M" },
      { action: "Toggle shuffle", keys: "Ctrl+S" },
      { action: "Cycle repeat", keys: "Ctrl+R" },
      { action: "Seek back 10 seconds", keys: "Shift+Left" },
      { action: "Seek forward 10 seconds", keys: "Shift+Right" },
      { action: "Raise volume 5%", keys: "Ctrl+Up" },
      { action: "Lower volume 5%", keys: "Ctrl+Down" },
      { section: "WINDOW", action: "Arm close / close", keys: "Esc, Esc" },
      { action: "Hide visible shortcut hints", keys: "Ctrl+H" },
      { action: "Show this reference", keys: "Ctrl+/" }
    ]
  }

  function scopedSearchText() {
    if (currentTab === "home") return homeFilter
    if (currentTab === "discover") return discoverFilter
    if (currentTab === "library") return libraryFilter
    if (currentTab === "playlists") return playlistFilter
    if (currentTab === "queue") return queueFilter
    if (currentTab === "detail") return activeSearchScope.mode === "artist"
      ? artistSearchText : detailFilter
    return ""
  }

  function setScopedSearchText(value) {
    var text = String(value || "")
    if (currentTab === "home") homeFilter = text
    else if (currentTab === "discover") discoverFilter = text
    else if (currentTab === "library") libraryFilter = text
    else if (currentTab === "playlists") playlistFilter = text
    else if (currentTab === "queue") queueFilter = text
    else if (currentTab === "detail") {
      if (activeSearchScope.mode === "artist") artistSearchText = text
      else detailFilter = text
    }
  }

  function unifiedSearchText() {
    return activeSearchScope.available && searchInContext
      ? scopedSearchText() : searchText
  }

  function searchScopeButtonText() {
    var label = activeSearchScope && activeSearchScope.label
      ? String(activeSearchScope.label) : "this area"
    if (label.length > 24) label = label.substring(0, 23) + "…"
    return "In " + label
  }

  function syncUnifiedSearchField() {
    if (!unifiedSearchField) return
    var next = unifiedSearchText()
    if (unifiedSearchField.text !== next)
      unifiedSearchField.text = next
  }

  function runUnifiedSearch() {
    unifiedSearchDelay.stop()
    if (!service) return
    if (activeSearchScope.available && searchInContext) {
      if (activeSearchScope.mode === "artist")
        service.findArtistMusic(artistSearchText)
      return
    }
    if (currentTab !== "search" && searchText.trim() !== "")
      universalSearchActive = true
    if (searchText.trim() === "") service.clearSearch()
    else service.search(searchText)
  }

  function editUnifiedSearch(value) {
    unifiedSearchDelay.stop()
    var text = String(value || "")
    if (activeSearchScope.available && searchInContext) {
      setScopedSearchText(text)
      if (activeSearchScope.mode === "artist") {
        if (text.trim() === "") {
          if (service) service.findArtistMusic("")
        } else {
          if (service) service.cancelArtistCatalog()
          unifiedSearchDelay.restart()
        }
      }
      return
    }
    searchText = text
    if (!service) return
    if (text.trim() === "") {
      service.clearSearch()
      if (currentTab !== "search") universalSearchActive = false
    } else {
      service.cancelSearch(false)
      unifiedSearchDelay.restart()
    }
  }

  function clearUnifiedSearch() {
    unifiedSearchDelay.stop()
    if (activeSearchScope.available && searchInContext) {
      setScopedSearchText("")
      if (activeSearchScope.mode === "artist" && service)
        service.findArtistMusic("")
    } else {
      searchText = ""
      if (service) service.clearSearch()
      if (currentTab !== "search") {
        universalSearchActive = false
        if (activeSearchScope.available) {
          searchInContext = true
          setScopedSearchText("")
          if (activeSearchScope.mode === "artist" && service)
            service.findArtistMusic("")
        }
      }
    }
    syncUnifiedSearchField()
  }

  function toggleSearchScope() {
    if (!activeSearchScope.available) return
    unifiedSearchDelay.stop()
    var text = unifiedSearchText()
    if (searchInContext) {
      searchText = text
      searchInContext = false
      universalSearchActive = true
      if (service) {
        if (searchText.trim() === "") service.clearSearch()
        else service.search(searchText)
      }
    } else {
      searchInContext = true
      universalSearchActive = false
      setScopedSearchText(text)
      if (service) {
        service.cancelSearch(false)
        if (activeSearchScope.mode === "artist")
          service.findArtistMusic(text)
      }
    }
    syncUnifiedSearchField()
    Qt.callLater(function() {
      unifiedSearchField.selectAll()
      unifiedSearchField.forceActiveFocus()
    })
  }

  // Popups live in their own files and hand focus back through this.
  function restoreFocus() {
    focusScope.forceActiveFocus()
  }

  // Focus without selecting, for the search-history chips.
  function focusSearchField() {
    unifiedSearchField.forceActiveFocus()
  }

  function focusSearch() {
    if (!unifiedSearchBar.visible) return
    unifiedSearchField.selectAll()
    unifiedSearchField.forceActiveFocus()
  }

  function activateSearch() {
    if (!unifiedSearchBar.visible) return
    var action = Api.searchShortcutAction(unifiedSearchField.activeFocus,
      activeSearchScope.available, searchInContext)
    if (action === "toggle-scope" || action === "enter-context")
      toggleSearchScope()
    else focusSearch()
  }

  function seekBy(seconds) {
    if (!service || !service.playbackControllable) return
    service.seekSeconds(Api.seekPosition(service.positionSeconds, seconds,
      service.lengthSeconds))
  }

  function setPanelVolume(value, live) {
    if (!service || !service.volumeSupported) return
    var next = Api.nextVolume(value, 0)
    if (Api.shouldRememberVolume(next)) volumeBeforeMute = next
    service.setVolume(next, live === true)
  }

  function adjustVolume(delta) {
    if (!service) return
    var now = Date.now()
    if (now - lastVolumeAdjustAt < 8) return
    lastVolumeAdjustAt = now
    setPanelVolume(Api.nextVolume(service.volume, delta))
  }

  function toggleMute() {
    if (!service || !service.volumeSupported) return
    var current = Api.nextVolume(service.volume, 0)
    if (Api.shouldRememberVolume(current)) {
      volumeBeforeMute = current
      service.setVolume(0)
    } else service.setVolume(Api.unmuteVolume(volumeBeforeMute))
  }

  function toggleShortcutHelp() {
    disarmEscapeClose()
    if (shortcutHelpPopup.opened) shortcutHelpPopup.close()
    else shortcutHelpPopup.open()
  }

  function openLyrics() {
    if (!service || !service.currentLyricsSong) return
    var result = service.requestLyrics(lyricsRequestKey)
    if (result !== "opening") lyricsInstallPopup.open()
  }

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(String(payloadJson || "{}")) || ({}) } catch (e) {}
    if (shell && shell.bar
        && typeof shell.bar.hideBarWidget === "function")
      shell.bar.hideBarWidget(pluginId)
    var requestedTab = String(payload.tab || "")
    var requestedDetail = requestedTab === "detail" && payload.detailItem
      ? payload.detailItem : null
    restoreUiState(!requestedDetail)
    if (requestedDetail) {
      currentTab = "detail"
      navigationStack = []
      searchInContext = true
      universalSearchActive = false
      artistSearchText = ""
      detailFilter = ""
    } else if (["home", "discover", "search", "library", "playlists", "queue", "devices", "setup"].indexOf(requestedTab) >= 0)
      currentTab = requestedTab
    if (accountConnected) {
      openedForLogin = false
    } else if (!sessionPending) {
      currentTab = "login"
      universalSearchActive = false
      searchInContext = true
      openedForLogin = true
    }
    closingFromHost = false
    opened = true
    if (payload.shortcutLatch) {
      latchShortcutMode()
      panelCursorActive = true
      ensurePanelCursor("footer")
    } else clearShortcutMode()
    syncDraftSettings()
    if (service) {
      service.setUiVisible("full-panel", true)
      service.activate(currentTab)
      restorePlaylistSelection()
      if (currentTab === "detail" && requestedDetail)
        service.openDetail(requestedDetail)
      if (currentTab === "search" && searchText && service.searchQuery !== searchText)
        service.search(searchText)
    }
    Qt.callLater(function() {
      focusScope.forceActiveFocus()
    })
  }

  function close() {
    persistUiState()
    clearShortcutMode()
    closingFromHost = true
    opened = false
    if (service) {
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
    closingFromHost = false
  }

  function requestClose() {
    disarmEscapeClose()
    if (shell && typeof shell.hide === "function") shell.hide(pluginId)
    else close()
  }

  function rememberCurrentContentTab() {
    var remembered = Api.rememberContentTab(currentTab)
    if (remembered) lastContentTab = remembered
  }

  function leaveUtilityTab() {
    var destination = Api.previousContentTab(currentTab, lastContentTab)
    if (!destination) return false
    disarmEscapeClose()
    chooseTab(destination)
    return true
  }

  function chooseTab(tab) {
    if (!accountConnected) {
      currentTab = "login"
      openedForLogin = true
      return
    }
    disarmEscapeClose()
    unifiedSearchDelay.stop()
    if (showingUniversalSearch && tab !== "search" && service) service.cancelSearch(false)
    searchInContext = true
    universalSearchActive = false
    rememberCurrentContentTab()
    currentTab = tab
    if (tab !== "detail") navigationStack = []
    openedForLogin = false
    if (service) {
      service.openView(tab, false)
      if (tab === "playlists") restorePlaylistSelection()
    }
    syncUnifiedSearchField()
  }

  function openLastRadio() {
    if (!service || !service.lastRadioPlaylist) return
    chooseTab("playlists")
    service.openPlaylist(service.lastRadioPlaylist)
  }

  function primaryNavigationItems() {
    var items = [
      { id: "home", label: "For you", icon: "󰎆" },
      { id: "discover", label: "Discover", icon: "󰲸" }
    ]
    if (service && service.lastRadioPlaylist) items.push({
      id: "radio",
      label: service.lastRadioPlaying ? "Current radio" : "Last radio",
      icon: "󰎆"
    })
    items.push({ id: "queue", label: "Queue", icon: "󰐕" })
    return items
  }

  function radioNavigationSelected() {
    return currentTab === "playlists" && service && service.lastRadioPlaylist
      && service.selectedPlaylist
      && String(service.selectedPlaylist.id) === String(service.lastRadioPlaylist.id)
  }

  function updateLoginGate() {
    if (!opened) return
    if (sessionPending) return
    if (!accountConnected) {
      currentTab = "login"
      universalSearchActive = false
      searchInContext = true
      openedForLogin = true
      return
    }
    if (openedForLogin || currentTab === "login") {
      openedForLogin = false
      currentTab = "home"
      universalSearchActive = false
      searchInContext = true
      if (service) service.openView("home", false)
    }
  }

  // Track the combined service state directly. During the first login, the
  // Web API token and playback credential finish in separate event turns;
  // listening only to those nested objects can miss the final combined edge
  // while the panel loader is being remapped by the browser.
  onShortcutHintsEnabledChanged: if (!shortcutHintsEnabled) clearShortcutMode()
  onCurrentTabChanged: {
    root.rememberCurrentContentTab()
    if (panelCursorActive) ensurePanelCursor()
  }
  onPanelCursorActionChanged: syncCollectionCursor()
  onPanelCursorRegionChanged: syncCollectionCursor()
  onPanelCursorActiveChanged: syncCollectionCursor()
  onShortcutModeLatchedChanged: syncCollectionCursor()
  onHeldModifierFlagsChanged: syncCollectionCursor()
  onFullyConnectedChanged: Qt.callLater(function() { root.updateLoginGate() })
  onAccountConnectedChanged: Qt.callLater(function() { root.updateLoginGate() })
  onSessionPendingChanged: Qt.callLater(function() { root.updateLoginGate() })
  onServiceChanged: Qt.callLater(function() { root.updateLoginGate() })


  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onPlaylistsChanged() { root.restorePlaylistSelection() }
    function onRadioPlaylistReady(playlist) {
      if (!playlist || !root.service) return
      root.openLastRadio()
    }
  }

  function pageComponent() {
    if (currentTab === "login") return loginPage
    if (showingUniversalSearch) return searchPage
    if (currentTab === "setup") return setupPage
    if (currentTab === "home") return homePage
    if (currentTab === "discover") return discoverPage
    if (currentTab === "library") return libraryPage
    if (currentTab === "playlists") return playlistsPage
    if (currentTab === "detail") return detailPage
    if (currentTab === "queue") return queuePage
    if (currentTab === "devices") return devicesPage
    return searchPage
  }

  function pageTitle() {
    if (currentTab === "login") return "Log in to Spotify"
    if (showingUniversalSearch) return "Search Spotify"
    if (currentTab === "home") return "For you"
    if (currentTab === "discover") return "Discover"
    if (currentTab === "library") return "Your Library"
    if (currentTab === "playlists") return "Playlists"
    if (currentTab === "queue") return "Queue"
    if (currentTab === "devices") return "Spotify Connect"
    if (currentTab === "setup") return "Settings"
    if (currentTab === "detail") {
      if (artistScopedSearchActive) return "Search in " + service.detailItem.name
      return service && service.detailItem ? service.detailItem.name : "Loading…"
    }
    return "Search"
  }

  function pageSubtitle() {
    if (currentTab === "login") return "Connect your Spotify account to get started"
    if (showingUniversalSearch) return activeSearchScope.available
      ? "Searching everywhere — enable the area checkmark to narrow the results"
      : "Songs, artists, albums, playlists, podcasts and audiobooks"
    if (currentTab === "home") return "Recently played and your personal favorites"
    if (currentTab === "discover") return "Personal mixes and fresh music from Spotify"
    if (currentTab === "library") return ""
    if (currentTab === "playlists") return "Your Spotify playlists"
    if (currentTab === "queue") return "What plays next"
    if (currentTab === "devices") return "Speakers and players"
    if (currentTab === "setup") return "Account, playback and app preferences"
    if (currentTab === "detail") {
      if (artistScopedSearchActive)
        return "Songs, albums and playlists matching “" + artistSearchText.trim() + "”"
      return service && service.detailItem
        ? Api.spotifyTypeLabel(service.detailItem.type) : "Spotify item"
    }
    return "Songs, artists, albums, playlists, podcasts and audiobooks"
  }

  function librarySortLabel() {
    var mode = service ? service.librarySort : "library"
    if (mode === "recent") return "Recents"
    if (mode === "added") return "Recently added"
    if (mode === "alpha") return "Alphabetical"
    return "Library order"
  }

  function cycleLibrarySort() {
    if (!service) return
    var modes = Api.librarySortModes()
    var at = modes.indexOf(service.librarySort)
    service.setLibrarySort(modes[(at + 1) % modes.length])
  }

  function libraryViewIcon() {
    var mode = service ? service.libraryView : "list"
    if (mode === "compact-list") return "󰉹"
    if (mode === "grid") return "󰕰"
    if (mode === "compact-grid") return "󰋣"
    return "󰋲"
  }

  function libraryViewLabel() {
    var mode = service ? service.libraryView : "list"
    if (mode === "compact-list") return "Compact list"
    if (mode === "grid") return "Grid"
    if (mode === "compact-grid") return "Compact grid"
    return "List"
  }

  function cycleLibraryView() {
    if (!service) return
    var modes = Api.libraryViewModes()
    var at = modes.indexOf(service.libraryView)
    service.setLibraryView(modes[(at + 1) % modes.length])
  }

  readonly property bool libraryViewIsGrid: service
    && service.libraryView.indexOf("grid") >= 0
  readonly property bool libraryViewIsCompact: service
    && service.libraryView.indexOf("compact") === 0
  readonly property int libraryRowHeight: libraryViewIsCompact
    ? Style.space(26) : Style.space(40)
  readonly property int libraryThumbSize: libraryViewIsCompact
    ? Style.space(20) : Style.space(32)

  function sidebarItemIcon(item) {
    if (item && item.pinned) return "󰐃"
    var type = item ? String(item.type || "playlist") : "playlist"
    if (type === "artist") return "󰠃"
    if (type === "album") return "󰀥"
    if (type === "show" || type === "episode") return "󰦔"
    return "󰲸"
  }

  function openSidebarItem(item) {
    if (!item || !service) return
    if (String(item.type || "playlist") === "playlist") {
      chooseTab("playlists")
      service.openPlaylist(item)
      return
    }
    openItem(item)
  }

  function sidebarPlaylistName(item) {
    var name = item && item.name ? String(item.name) : "Playlist"
    return name.length > 22 ? name.substring(0, 21) + "…" : name
  }

  function playlistOptions() {
    var playlists = service ? service.sidebarPlaylists() : []
    var options = []
    for (var i = 0; i < playlists.length; i++) {
      var playlist = playlists[i]
      if (!playlist || !playlist.id) continue
      options.push({
        value: String(playlist.id),
        label: String(playlist.name || "Playlist"),
        description: String(playlist.ownerName || "")
      })
    }
    return options
  }

  function openExternal(item) {
    if (item && item.externalUrl) Qt.openUrlExternally(item.externalUrl)
  }

  function copyExternal(item) {
    if (!item || !item.externalUrl) return
    Quickshell.execDetached(["wl-copy", String(item.externalUrl)])
    if (service) service.succeed("Spotify link copied")
  }

  function playlistPosition(item, sourceItems) {
    if (!service || !item || !contextPlaylist) return -1
    var source = sourceItems === undefined
      ? contextPlaylistItems() : Api.arrayValues(sourceItems)
    var occurrence = 0
    for (var shown = 0; shown < contextSourceIndex; shown++)
      if (contextSourceItems[shown] && contextSourceItems[shown].uri === item.uri) occurrence++
    for (var i = 0; i < source.length; i++) {
      if (source[i] && source[i].uri === item.uri) {
        if (occurrence === 0) return i
        occurrence--
      }
    }
    return -1
  }

  function contextPlaylistItems() {
    return Api.playlistBackingItems(contextPlaylist,
      service ? service.selectedPlaylist : null,
      service ? service.playlistItems : [],
      service ? service.detailItem : null,
      service ? service.detailItems : [])
  }

  function contextPlaylistMoveSpec(delta) {
    var items = contextPlaylistItems()
    var position = playlistPosition(contextItem, items)
    var direction = Number(delta) < 0 ? -1 : (Number(delta) > 0 ? 1 : 0)
    var destination = position >= 0 && direction
      ? Api.listIndexAfterMove(items.length, position, direction) : -1
    return {
      available: !!service && !!contextPlaylist && destination >= 0,
      playlist: contextPlaylist,
      position: position,
      direction: direction,
      count: items.length
    }
  }

  function moveContextPlaylistItem(delta) {
    var action = contextPlaylistMoveSpec(delta)
    var actionService = service
    if (!action.available || !actionService) return
    mediaContextMenu.close()
    actionService.movePlaylistItem(action.position, action.direction,
      action.playlist, action.count)
  }

  function openPlaylistPicker(item) {
    if (!item || item.kind !== "item") return
    pendingPlaylistItem = item
    playlistPicker.open()
  }

  function openCreatePlaylistPopup() {
    if (!service || !accountConnected) return
    createPlaylistName = ""
    createPlaylistPopup.open()
  }

  function createNamedPlaylist() {
    var name = String(createPlaylistName || "").trim()
    if (!service || !name || service.playlistActionBusy) return
    service.createPlaylist(name, function(playlist) {
      createPlaylistPopup.close()
      createPlaylistName = ""
      if (!playlist) return
      root.chooseTab("playlists")
      root.service.openPlaylist(playlist)
    })
  }

  Component.onDestruction: {
    if (service) {
      persistUiState()
      service.setUiVisible("full-panel", false)
      service.cancelSearch(false)
    }
  }

  ShortcutHelpPopup {
    id: shortcutHelpPopup
    panel: root
  }

  LyricsInstallPopup {
    id: lyricsInstallPopup
    panel: root
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onLyricsPluginPromptRequested(surface, availability) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.open()
    }
    function onLyricsPluginOpened(surface) {
      if (String(surface) === root.lyricsRequestKey) lyricsInstallPopup.close()
    }
  }

  MediaContextMenu {
    id: mediaContextMenu
    panel: root
  }

  PlaylistPicker {
    id: playlistPicker
    panel: root
  }

  CreatePlaylistPopup {
    id: createPlaylistPopup
    panel: root
  }

  SleepPopup {
    id: sleepPopup
    panel: root
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "OmaSpotify"
    color: root.background
    implicitWidth: 980
    implicitHeight: 720
    minimumSize: Qt.size(700, 560)

    onVisibleChanged: {
      if (!visible && root.opened && !root.closingFromHost) root.requestClose()
    }
    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true
      Keys.priority: Keys.BeforeItem
      onActiveFocusChanged: if (!activeFocus) {
        root.heldModifierFlags = 0
        root.shortcutModeLatched = false
      }
      Keys.onShortcutOverride: function(event) {
        if (shortcutModifiers.isHintModifierKey(event.key) && !root.typingInField) {
          root.considerShortcutModeKey(event, true)
          event.accepted = true
          return
        }
        if (root.typingInField) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
            || event.key === Qt.Key_F6)
          event.accepted = true
        if (!root.shortcutsBlocked && root.service && root.service.volumeSupported
            && (event.modifiers & Qt.ControlModifier)
            && !(event.modifiers & Qt.ShiftModifier)
            && !(event.modifiers & Qt.AltModifier)
            && (event.key === Qt.Key_Up || event.key === Qt.Key_Down))
          event.accepted = true
      }
      Keys.onPressed: function(event) {
        root.considerShortcutModeKey(event, true)
        if (shortcutModifiers.isHintModifierKey(event.key) && !root.typingInField) {
          event.accepted = true
          return
        }
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) return
        if (root.handlePanelCursorKey(event)) event.accepted = true
      }
      Keys.onReturnPressed: function(event) {
        if (root.handlePanelCursorKey(event)) event.accepted = true
      }
      Keys.onEnterPressed: function(event) {
        if (root.handlePanelCursorKey(event)) event.accepted = true
      }
      Keys.onReleased: function(event) {
        root.noteHeldModifiers(event, false)
        if (shortcutModifiers.isHintModifierKey(event.key) && !root.typingInField)
          event.accepted = true
      }
      Keys.onEscapePressed: function(event) {
        root.latchShortcutMode()
        if (root.dismissTransientPopup()) {
          root.disarmEscapeClose()
          event.accepted = true
          return
        }
        if (root.dismissSearch()) {
          event.accepted = true
          return
        }
        if (root.leaveUtilityTab()) {
          event.accepted = true
          return
        }
        if (root.currentTab === "detail" || root.navigationStack.length) {
          root.disarmEscapeClose()
          root.goBack()
        } else if (root.escapeCloseArmed) root.requestClose()
        else root.armEscapeClose()
        event.accepted = true
      }

      Shortcut {
        sequence: "/"
        enabled: unifiedSearchBar.visible && !root.shortcutsBlocked
          && !root.textInputFocused()
        onActivated: {
          root.latchShortcutMode(sequence)
          root.activateSearch()
        }
      }
      Shortcut {
        sequence: "Ctrl+F"
        enabled: unifiedSearchBar.visible && !root.shortcutsBlocked
          && !unifiedSearchField.activeFocus
        onActivated: {
          root.latchShortcutMode(sequence)
          root.activateSearch()
        }
      }
      Shortcut {
        sequence: "C"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: {
          root.latchShortcutMode(sequence)
          root.openCurrentContextMenu()
        }
      }
      Shortcut {
        sequence: "Menu"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: {
          root.latchShortcutMode(sequence)
          root.openCurrentContextMenu()
        }
      }
      Shortcut {
        sequence: "Shift+F10"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
        onActivated: {
          root.latchShortcutMode(sequence)
          root.openCurrentContextMenu()
        }
      }
      Shortcut {
        sequence: "Alt+Left"
        enabled: !root.shortcutsBlocked
          && (root.currentTab === "detail" || root.navigationStack.length > 0)
        onActivated: {
          root.latchShortcutMode(sequence)
          root.goBack()
        }
      }
      Shortcut {
        sequence: "Ctrl+,"
        enabled: root.accountConnected && !root.shortcutsBlocked
        onActivated: {
          root.latchShortcutMode(sequence)
          root.chooseTab("setup")
        }
      }
      Shortcut {
        sequence: "Alt+Shift+H"
        enabled: root.accountConnected && !root.shortcutsBlocked
        onActivated: {
          root.latchShortcutMode(sequence)
          root.chooseTab("home")
        }
      }
      Shortcut {
        sequence: "Alt+Shift+Q"
        enabled: root.accountConnected && !root.shortcutsBlocked
        onActivated: {
          root.latchShortcutMode(sequence)
          root.chooseTab("queue")
        }
      }
      Shortcut {
        sequence: "Alt+Shift+D"
        enabled: root.accountConnected && !root.shortcutsBlocked
        onActivated: {
          root.latchShortcutMode(sequence)
          root.chooseTab("devices")
        }
      }
      Shortcut {
        sequence: "Ctrl+Shift+A"
        enabled: root.accountConnected && !root.shortcutsBlocked
          && root.service && root.service.currentArtistContextAvailable
        onActivated: {
          root.latchShortcutMode(sequence)
          root.openCurrentArtist()
        }
      }
      Shortcut {
        sequence: "Ctrl+Shift+B"
        enabled: root.accountConnected && !root.shortcutsBlocked
          && root.service && root.service.currentAlbumContextAvailable
        onActivated: {
          root.latchShortcutMode(sequence)
          root.openCurrentAlbum()
        }
      }
      Shortcut {
        sequence: "Ctrl+Shift+L"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.lyricsAvailable
        onActivated: {
          root.latchShortcutMode(sequence)
          root.openLyrics()
        }
      }
      Shortcut {
        sequence: "Space"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: {
          root.latchShortcutMode(sequence)
          if (root.service) root.service.togglePlayback()
        }
      }
      Shortcut {
        sequence: "Ctrl+Right"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: {
          root.latchShortcutMode(sequence)
          if (root.service) root.service.next()
        }
      }
      Shortcut {
        sequence: "Ctrl+Left"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: {
          root.latchShortcutMode(sequence)
          if (root.service) root.service.previous()
        }
      }
      Shortcut {
        sequence: "M"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.volumeSupported
        onActivated: {
          root.latchShortcutMode(sequence)
          root.toggleMute()
        }
      }
      Shortcut {
        sequence: "Ctrl+S"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: {
          root.latchShortcutMode(sequence)
          root.service.setShuffle(!root.service.shuffle)
        }
      }
      Shortcut {
        sequence: "Ctrl+R"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: {
          root.latchShortcutMode(sequence)
          root.service.cycleRepeat()
        }
      }
      Shortcut {
        sequence: "Shift+Left"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: {
          root.latchShortcutMode(sequence)
          root.seekBy(-10)
        }
      }
      Shortcut {
        sequence: "Shift+Right"
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.playbackControllable
        onActivated: {
          root.latchShortcutMode(sequence)
          root.seekBy(10)
        }
      }
      Shortcut {
        sequence: "Ctrl+Up"
        autoRepeat: false
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.volumeSupported
        onActivated: {
          root.latchShortcutMode(sequence)
          root.adjustVolume(0.05)
        }
      }
      Shortcut {
        sequence: "Ctrl+Down"
        autoRepeat: false
        enabled: !root.shortcutsBlocked && !root.textInputFocused()
          && root.service && root.service.volumeSupported
        onActivated: {
          root.latchShortcutMode(sequence)
          root.adjustVolume(-0.05)
        }
      }
      Shortcut {
        sequence: "Ctrl+/"
        enabled: !root.textInputFocused()
          && (!root.shortcutsBlocked || shortcutHelpPopup.opened)
        onActivated: {
          root.latchShortcutMode(sequence)
          root.toggleShortcutHelp()
        }
      }
      Shortcut {
        sequence: "Ctrl+H"
        enabled: root.shortcutHintsActive
        onActivated: root.disableShortcutHints()
      }

      Item {
        anchors.fill: parent
        anchors.margins: Style.space(14)

        Row {
          id: workspace
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.bottom: footerSeparator.top
          anchors.bottomMargin: Style.space(10)
          spacing: sidebar.visible ? Style.space(10) : 0

          BorderSurface {
            id: sidebar
            visible: root.currentTab !== "login"
            width: visible
              ? (root.compactWidth ? Style.space(54)
                : Math.min(Style.space(214), Math.max(Style.space(176), workspace.width * 0.225)))
              : 0
            height: parent.height
            color: "transparent"
            borderSpec: Border.none()

            Row {
              id: brandRow
              visible: !root.compactHeight
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: visible ? Style.space(2) : 0
              height: visible ? Style.space(24) : 0
              spacing: Style.space(9)

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: ""
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
              }

              Column {
                visible: !root.compactWidth
                width: Math.max(40, parent.width - Style.space(38))
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                  width: parent.width
                  text: root.appName
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
              }
            }

            Column {
              id: primaryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: brandRow.visible ? brandRow.bottom : parent.top
              anchors.margins: Style.space(2)
              anchors.topMargin: Style.space(8)
              spacing: Style.space(2)

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }

              Repeater {
                model: root.primaryNavigationItems()

                Button {
                  required property var modelData
                  readonly property bool radioEntry: modelData.id === "radio"
                  width: primaryNavigation.width
                  text: root.compactWidth ? "" : modelData.label
                  iconText: modelData.icon
                  foreground: root.foreground
                  selected: radioEntry ? root.radioNavigationSelected()
                    : root.currentTab === modelData.id
                  leftAlign: !root.compactWidth
                  focusable: false
                  hasCursor: root.cursorOn("sidebar", "nav-" + modelData.id)
                  tooltipText: radioEntry && root.service && root.service.lastRadioPlaylist
                    ? modelData.label + " · " + root.service.lastRadioPlaylist.name
                    : root.shortcutHint(modelData.label,
                      root.primaryNavigationShortcut(modelData.id))
                  onClicked: {
                    if (radioEntry) root.openLastRadio()
                    else root.chooseTab(modelData.id)
                  }
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("sidebar", "nav-" + modelData.id)
                  }
                  KeyHint {
                    region: "sidebar"
                    action: "nav-" + modelData.id
                    sequences: root.primaryNavigationShortcut(modelData.id)
                  }
                }
              }

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }
            }

            Text {
              id: playlistShortcutsHeading
              visible: false
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: primaryNavigation.bottom
              anchors.leftMargin: Style.space(2)
              anchors.rightMargin: Style.space(2)
              anchors.topMargin: Style.space(8)
              height: 0
              text: ""
            }

            Column {
              id: libraryNavigation
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: playlistShortcutsHeading.visible
                ? playlistShortcutsHeading.bottom : primaryNavigation.bottom
              anchors.leftMargin: Style.space(2)
              anchors.rightMargin: Style.space(2)
              anchors.topMargin: Style.space(6)
              spacing: Style.space(2)

              Button {
                width: parent.width
                text: root.compactWidth ? "" : "Liked Songs"
                iconText: "󰋑"
                foreground: root.foreground
                selected: root.currentTab === "library"
                leftAlign: !root.compactWidth
                focusable: false
                hasCursor: root.cursorOn("sidebar", "nav-library")
                tooltipText: "Liked Songs"
                onClicked: root.chooseTab("library")
                onHovered: function(on) {
                  if (on) root.setPanelCursor("sidebar", "nav-library")
                }
                KeyHint { region: "sidebar"; action: "nav-library" }
              }

              Row {
                width: parent.width
                spacing: Style.space(2)

                Button {
                  width: Math.max(20, parent.width - createPlaylistShortcut.width
                    - parent.spacing)
                  text: root.compactWidth ? "" : "Playlists"
                  iconText: "󱁐"
                  foreground: root.foreground
                  selected: root.currentTab === "playlists"
                  leftAlign: !root.compactWidth
                  focusable: false
                  hasCursor: root.cursorOn("sidebar", "nav-playlists")
                  tooltipText: "Playlists"
                  onClicked: root.chooseTab("playlists")
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("sidebar", "nav-playlists")
                  }
                  KeyHint { region: "sidebar"; action: "nav-playlists" }
                }

                Button {
                  id: createPlaylistShortcut
                  width: root.compactWidth
                    ? Math.max(20, (parent.width - parent.spacing) / 2) : implicitWidth
                  text: "+"
                  foreground: root.foreground
                  fontSize: Style.font.subtitle
                  horizontalPadding: Style.space(7)
                  focusable: false
                  hasCursor: root.cursorOn("sidebar", "nav-create")
                  tooltipText: "Create a new playlist"
                  enabled: root.accountConnected && root.service
                    && !root.service.playlistActionBusy
                  onClicked: root.openCreatePlaylistPopup()
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("sidebar", "nav-create")
                  }
                  KeyHint { region: "sidebar"; action: "nav-create" }
                }
              }
            }

            Row {
              id: libraryControls
              visible: !root.compactWidth
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: libraryNavigation.bottom
              anchors.margins: Style.space(2)
              anchors.topMargin: Style.space(6)
              height: visible ? implicitHeight : 0
              spacing: Style.space(2)

              Button {
                id: librarySortButton
                width: Math.max(40, parent.width - libraryViewButton.width
                  - parent.spacing)
                text: root.librarySortLabel()
                iconText: "󰒺"
                foreground: root.muted
                leftAlign: true
                focusable: false
                tooltipText: "Sort the library"
                onClicked: root.cycleLibrarySort()
              }

              Button {
                id: libraryViewButton
                iconText: root.libraryViewIcon()
                foreground: root.muted
                focusable: false
                tooltipText: "View · " + root.libraryViewLabel()
                onClicked: root.cycleLibraryView()
              }
            }

            GridView {
              id: playlistGrid
              visible: !root.compactWidth && root.libraryViewIsGrid
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: libraryControls.bottom
              anchors.bottom: setupNavButton.top
              anchors.margins: Style.space(2)
              model: root.service ? root.service.sidebarItems : []
              cellWidth: Math.max(Style.space(56),
                Math.floor(width / Math.max(1, Math.floor(width / Style.space(84)))))
              cellHeight: root.libraryViewIsCompact
                ? cellWidth : cellWidth + Style.space(16)
              clip: true
              reuseItems: true
              keyNavigationEnabled: false

              delegate: SidebarRow {
                required property var modelData
                width: playlistGrid.cellWidth
                height: playlistGrid.cellHeight
                item: modelData
                compact: root.libraryViewIsCompact
                grid: true
                thumbnailSize: Math.min(width, height) - Style.space(10)
                fallbackGlyph: root.sidebarItemIcon(modelData)
                foreground: root.foreground
                accent: root.accent
                muted: root.muted
                fontFamily: root.fontFamily
                selected: root.currentTab === "playlists" && root.service
                  && root.service.selectedPlaylist
                  && root.service.selectedPlaylist.id === modelData.id
                onActivated: root.openSidebarItem(modelData)
                onContextRequested: {
                  if (root.service) root.service.togglePinnedItem(modelData)
                }
              }
            }

            ListView {
              id: playlistShortcuts
              visible: !root.compactWidth && !root.libraryViewIsGrid
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: libraryControls.bottom
              anchors.bottom: setupNavButton.top
              anchors.margins: Style.space(2)
              model: root.service ? root.service.sidebarItems : []
              clip: true
              spacing: Style.space(1)
              reuseItems: true
              keyNavigationEnabled: false
              highlightFollowsCurrentItem: true

              FastScrollHandler {
                parent: playlistShortcuts
                flickable: playlistShortcuts
                onScrolled: {
                  if (playlistShortcuts.atYEnd && root.service
                      && root.service.playlistsNext
                      && !root.service.playlistsLoading)
                    root.service.loadMorePlaylists()
                }
              }

              onMovementEnded: {
                if (atYEnd && root.service && root.service.playlistsNext
                    && !root.service.playlistsLoading) root.service.loadMorePlaylists()
              }

              delegate: SidebarRow {
                required property var modelData
                required property int index
                width: ListView.view.width
                height: root.libraryRowHeight
                item: modelData
                compact: root.libraryViewIsCompact
                grid: false
                thumbnailSize: root.libraryThumbSize
                fallbackGlyph: root.sidebarItemIcon(modelData)
                foreground: root.foreground
                accent: root.accent
                muted: root.muted
                fontFamily: root.fontFamily
                hasCursor: root.cursorOn("sidebar", "sidebar-playlists")
                  && ListView.isCurrentItem
                selected: root.currentTab === "playlists" && root.service
                  && root.service.selectedPlaylist
                  && root.service.selectedPlaylist.id === modelData.id
                onActivated: root.openSidebarItem(modelData)
                onContextRequested: {
                  if (root.service) root.service.togglePinnedItem(modelData)
                }
                onHoveredChanged: {
                  if (!hovered) return
                  playlistShortcuts.currentIndex = index
                  root.setPanelCursor("sidebar", "sidebar-playlists")
                }
                KeyHint {
                  active: root.shortcutHintsActive
                  navHint: {
                    playlistShortcuts.currentIndex
                    playlistShortcuts.contentY
                    root.panelCursorAction
                    root.panelCursorRegion
                    root.hintCtrlHeld
                    root.hintShiftHeld
                    root.hintAltHeld
                    return root.sidebarPlaylistNavHint(index)
                  }
                }
              }
            }

            Button {
              id: setupNavButton
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: Style.space(2)
              text: root.compactWidth ? "" : "Settings"
              iconText: root.service && root.service.auth.loggedIn ? "󰀄" : "󰒓"
              foreground: root.foreground
              selected: root.currentTab === "setup"
              leftAlign: !root.compactWidth
              focusable: false
              hasCursor: root.cursorOn("sidebar", "nav-settings")
              tooltipText: root.shortcutHint("Settings", "Ctrl+,")
              KeyHint { region: "sidebar"; action: "nav-settings"; sequences: ["Ctrl+,"] }
              onClicked: root.chooseTab("setup")
              onHovered: function(on) {
                if (on) root.setPanelCursor("sidebar", "nav-settings")
              }
            }
          }

          Item {
            id: contentPane
            width: Math.max(220, parent.width - sidebar.width - workspace.spacing)
            height: parent.height

            Row {
              id: pageHeader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              height: Math.max(closeButton.implicitHeight, titleColumn.implicitHeight)
              spacing: Style.space(5)

              Button {
                id: backButton
                visible: root.currentTab === "detail" || root.navigationStack.length > 0
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰁍"
                foreground: root.foreground
                tooltipText: root.shortcutHint("Back", "Alt+Left")
                focusable: false
                hasCursor: root.cursorOn("header", "back")
                onClicked: root.goBack()
                onHovered: function(on) { if (on) root.setPanelCursor("header", "back") }
                KeyHint { region: "header"; action: "back"; sequences: ["Alt+Left"] }
              }

              Column {
                id: titleColumn
                width: Math.max(80, parent.width
                  - (backButton.visible ? backButton.width + parent.spacing : 0)
                  - (shortcutHintsDismissButton.visible
                    ? shortcutHintsDismissButton.width : 0)
                  - shortcutHelpButton.width - refreshButton.width - closeButton.width
                  - parent.spacing * (shortcutHintsDismissButton.visible ? 4 : 3))
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(1)

                Text {
                  width: parent.width
                  text: root.pageTitle()
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.pageSubtitle()
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }
              }

              Button {
                id: shortcutHintsDismissButton
                visible: root.shortcutHintsActive
                anchors.verticalCenter: parent.verticalCenter
                text: "Ctrl+H · Hide hints"
                foreground: root.foreground
                fontSize: Style.font.caption
                focusable: false
                tooltipText: "Hide shortcut hints until re-enabled in Settings · Ctrl+H"
                onClicked: root.disableShortcutHints()
              }

              Button {
                id: shortcutHelpButton
                anchors.verticalCenter: parent.verticalCenter
                text: "?"
                foreground: root.foreground
                fontSize: Style.font.subtitle
                tooltipText: root.shortcutHint("Keyboard shortcuts", "Ctrl+/")
                focusable: false
                hasCursor: root.cursorOn("header", "help")
                onClicked: root.toggleShortcutHelp()
                onHovered: function(on) { if (on) root.setPanelCursor("header", "help") }
                KeyHint { region: "header"; action: "help"; sequences: ["Ctrl+/"] }
              }

              Button {
                id: refreshButton
                visible: root.currentTab !== "login" && root.currentTab !== "setup"
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰑐"
                foreground: root.foreground
                tooltipText: "Refresh"
                focusable: false
                hasCursor: root.cursorOn("header", "refresh")
                onHovered: function(on) {
                  if (on) root.setPanelCursor("header", "refresh")
                }
                KeyHint { region: "header"; action: "refresh" }
                onClicked: {
                  if (!root.service) return
                  if (root.showingUniversalSearch) root.runUnifiedSearch()
                  else if (root.currentTab === "detail" && root.service.detailItem)
                    root.service.openDetail(root.service.detailItem,
                      root.service.detailItem.type === "artist"
                        ? root.artistSearchText : "")
                  else if (root.currentTab === "library")
                    root.service.loadLibrary(root.libraryType, false, true)
                  else root.service.refreshView(root.currentTab)
                }
              }

              Button {
                id: closeButton
                anchors.verticalCenter: parent.verticalCenter
                iconText: "󰅖"
                foreground: root.escapeCloseArmed ? Color.urgent : root.foreground
                bordered: root.escapeCloseArmed
                borderSpec: root.escapeCloseArmed
                  ? Border.flat(Color.urgent, Math.max(1, Style.normalBorderWidth))
                  : closeButton._borderSpec
                tooltipText: root.escapeCloseArmed
                  ? "Press Esc again to close"
                  : root.shortcutHint("Close", "Esc, Esc")
                focusable: false
                hasCursor: root.cursorOn("header", "close")
                onClicked: root.requestClose()
                onHovered: function(on) { if (on) root.setPanelCursor("header", "close") }
                KeyHint { region: "header"; action: "close"; sequences: ["Esc"] }
              }
            }

            BorderSurface {
              id: statusBanner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: pageHeader.bottom
              anchors.topMargin: visible ? Style.space(6) : 0
              implicitHeight: visible ? messageText.implicitHeight + Style.space(12) : 0
              height: implicitHeight
              visible: root.service && (root.service.lastError !== "" || root.service.statusMessage !== "")
              color: root.service && root.service.lastError !== ""
                ? Style.selectedFillFor(root.foreground, Color.urgent)
                : Style.normalFillFor(root.foreground, root.accent)
              borderSpec: Border.controlSpec("normal", root.foreground,
                root.service && root.service.lastError !== "" ? Color.urgent : root.accent)
              radius: Style.cornerRadius

              Text {
                id: messageText
                anchors.fill: parent
                anchors.margins: Style.space(6)
                text: !root.service ? "" : (root.service.lastError || root.service.statusMessage)
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
              }
            }

            Row {
              id: unifiedSearchBar
              visible: root.currentTab !== "login" && root.currentTab !== "devices"
                && root.currentTab !== "setup"
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: statusBanner.visible ? statusBanner.bottom : pageHeader.bottom
              anchors.topMargin: visible ? Style.space(8) : 0
              height: visible ? Style.space(38) : 0
              spacing: Style.space(6)

              TextField {
                id: unifiedSearchField
                width: searchScopeButton.visible
                  ? Math.max(0, parent.width - searchScopeButton.width
                    - parent.spacing)
                  : parent.width
                height: parent.height
                foreground: root.foreground
                placeholderText: root.activeSearchScope.available && root.searchInContext
                  ? "Search in " + root.activeSearchScope.label : "Search Spotify"
                enabled: root.service && root.service.auth.loggedIn
                hasCursor: root.cursorOn("header", "search")
                onTextEdited: root.editUnifiedSearch(text)
                onAccepted: root.runUnifiedSearch()

                Binding {
                  target: unifiedSearchField
                  property: "text"
                  value: root.unifiedSearchText()
                  when: !unifiedSearchField.activeFocus
                  restoreMode: Binding.RestoreNone
                }
                Keys.onPressed: function(event) {
                  var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
                  var shift = (event.modifiers & Qt.ShiftModifier) !== 0
                  var alt = (event.modifiers & Qt.AltModifier) !== 0
                  if (event.key === Qt.Key_Escape) {
                    root.latchShortcutMode()
                    if (root.dismissSearch()) {
                      event.accepted = true
                      return
                    }
                  }
                  if (ctrl && !shift && !alt && event.key === Qt.Key_F) {
                    root.latchShortcutMode("Ctrl+F")
                    root.activateSearch()
                    event.accepted = true
                    return
                  }
                  if (!ctrl && !shift && !alt
                      && (event.key === Qt.Key_Slash || event.text === "/")) {
                    root.latchShortcutMode("/")
                    root.activateSearch()
                    event.accepted = true
                  }
                }

                PanelToolTip {
                  visible: unifiedSearchField.hovered
                  text: root.activeSearchScope.available
                    ? "Search · Ctrl+F or /\nPress again to toggle this area and all of Spotify"
                    : "Search · Ctrl+F or /"
                }
                KeyHint { region: "header"; action: "search"; sequences: ["/", "Ctrl+F"] }
              }

              Button {
                id: searchScopeButton
                visible: root.activeSearchScope.available
                width: visible ? Math.min(parent.width * 0.4,
                  Math.max(parent.width * 0.2, implicitWidth)) : 0
                height: parent.height
                clip: true
                anchors.verticalCenter: parent.verticalCenter
                text: root.searchScopeButtonText()
                iconText: root.searchInContext ? "󰄬" : "󰄱"
                foreground: root.foreground
                selected: root.searchInContext
                bordered: true
                focusable: false
                hasCursor: root.cursorOn("header", "scope")
                onHovered: function(on) {
                  if (on) root.setPanelCursor("header", "scope")
                }
                horizontalPadding: Style.space(8)
                tooltipText: root.searchInContext
                  ? root.shortcutHint("Search all of Spotify", "Ctrl+F or /")
                  : root.shortcutHint("Search only in "
                    + root.activeSearchScope.label, "Ctrl+F or /")
                onClicked: root.toggleSearchScope()
                KeyHint {
                  region: "header"
                  action: "scope"
                  sequences: ["/", "Ctrl+F"]
                  active: root.shortcutHintsEnabled && root.shortcutModeLatched
                    && !root.shortcutsBlocked
                    && (root.shortcutHintsActive || unifiedSearchField.activeFocus)
                }
              }
            }

            Loader {
              id: pageLoader
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: unifiedSearchBar.visible ? unifiedSearchBar.bottom
                : (statusBanner.visible ? statusBanner.bottom : pageHeader.bottom)
              anchors.topMargin: Style.space(8)
              anchors.bottom: parent.bottom
              sourceComponent: root.pageComponent()
            }
          }
        }

        PanelSeparator {
          id: footerSeparator
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: playerFooter.top
          anchors.bottomMargin: Style.space(4)
          foreground: root.foreground
        }

        BorderSurface {
          id: playerFooter
          visible: root.currentTab !== "login"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: visible ? Style.space(root.compactHeight ? 72 : 84) : 0
          color: "transparent"
          borderSpec: Border.none()

          Row {
            id: playerRow
            anchors.fill: parent
            anchors.margins: Style.space(2)
            anchors.leftMargin: 0
            anchors.rightMargin: 0
            spacing: Style.space(12)

            Item {
              id: nowPlaying
              width: Math.max(Style.space(170), Math.min(Style.space(240), playerRow.width * 0.29))
              height: parent.height
              readonly property real metadataSpacing: Style.space(9)

              BorderSurface {
                id: nowPlayingArtwork
                width: Math.min(parent.height, Style.space(68))
                height: width
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                radius: Style.cornerRadius
                color: Style.selectedFillFor(root.foreground, root.accent)
                borderSpec: Border.controlSpec("normal", root.foreground, root.accent)

                Image {
                  anchors.fill: parent
                  anchors.margins: Style.space(2)
                  source: root.service ? root.service.artUrl : ""
                  sourceSize.width: 136
                  sourceSize.height: 136
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  cache: true
                  visible: status === Image.Ready
                }

                Text {
                  anchors.centerIn: parent
                  visible: !root.service || root.service.artUrl === ""
                  text: "󰎈"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                }

              }

              Column {
                anchors.left: nowPlayingArtwork.right
                anchors.leftMargin: nowPlaying.metadataSpacing
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(3)

                Row {
                  width: parent.width
                  spacing: Style.space(3)

                  Text {
                    width: Math.max(20, parent.width
                      - (nowPlayingActions.visible
                        ? nowPlayingActions.width + parent.spacing : 0))
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.service && root.service.title
                      ? root.service.title : "Nothing playing"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Row {
                    id: nowPlayingActions
                    visible: currentTrackLikeButton.visible
                      || currentTrackMoreButton.visible
                    spacing: Style.space(1)
                    anchors.verticalCenter: parent.verticalCenter

                    Button {
                      id: currentTrackLikeButton
                      objectName: "current-track-like"
                      visible: root.service && !!root.service.currentTrackItem
                      iconText: root.service && root.service.currentTrackSaved
                        ? "󰋑" : "󰋕"
                      iconSize: Style.font.body
                      foreground: Color.urgent
                      accent: Color.urgent
                      enabled: root.service && root.service.currentTrackSaveAvailable
                      horizontalPadding: Style.space(4)
                      verticalPadding: Style.space(2)
                      tooltipText: root.service && root.service.currentTrackSaveChecking
                        ? "Checking liked status…"
                        : (root.service && root.service.currentTrackSaveBusy
                          ? "Updating liked status…"
                          : (root.service && root.service.currentTrackSaved
                            ? "Remove like" : "Like this song"))
                      hasCursor: root.cursorOn("footer", "like")
                      onClicked: if (root.service)
                        root.service.toggleCurrentTrackSaved()
                      onHovered: function(on) {
                        if (on) root.setPanelCursor("footer", "like")
                      }
                      KeyHint { region: "footer"; action: "like" }
                    }

                    Button {
                      id: currentTrackMoreButton
                      objectName: "current-track-more"
                      visible: root.service && !!root.service.currentTrackItem
                      iconText: "󰇙"
                      iconSize: Style.font.body
                      foreground: root.foreground
                      horizontalPadding: Style.space(4)
                      verticalPadding: Style.space(2)
                      tooltipText: root.shortcutHint("Song actions", "C")
                      hasCursor: root.cursorOn("footer", "context")
                      onClicked: root.openNowPlayingContext()
                      onHovered: function(on) {
                        if (on) root.setPanelCursor("footer", "context")
                      }
                      KeyHint {
                        region: "footer"
                        action: "context"
                        sequences: ["C"]
                      }
                    }
                  }
                }

                CursorSurface {
                  id: currentArtistCursor
                  z: 2
                  clip: false
                  width: parent.width
                  height: currentArtistLinks.implicitHeight
                  hasCursor: root.cursorOn("footer", "artist")
                  foreground: root.foreground
                  HoverHandler {
                    id: currentArtistHover
                    onHoveredChanged: if (hovered)
                      root.setPanelCursor("footer", "artist")
                  }
                  PanelToolTip {
                    visible: currentArtistHover.hovered
                    text: root.shortcutHint("Open artist", "Ctrl+Shift+A")
                  }

                  ArtistLinks {
                    id: currentArtistLinks
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: currentArtistHint.reservedRight
                    anchors.verticalCenter: parent.verticalCenter
                    artists: root.service ? root.service.currentArtists : []
                    fallbackText: root.service && root.service.artist
                      ? root.service.artist : "Choose something to play"
                    fallbackClickable: root.service && root.service.artist !== ""
                      && root.service.currentArtistContextAvailable
                      && artists.length === 0
                    color: root.service && root.service.artist
                      && root.service.currentArtistContextAvailable ? root.accent
                      : root.muted
                    accent: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    onArtistRequested: function(item) { root.openItem(item) }
                    onFallbackRequested: root.openCurrentArtist()
                  }

                  KeyHint {
                    id: currentArtistHint
                    region: "footer"
                    action: "artist"
                    sequences: ["Ctrl+Shift+A"]
                  }
                }

                CursorSurface {
                  id: currentAlbumCursor
                  z: 1
                  clip: false
                  width: parent.width
                  height: currentAlbumLinks.implicitHeight
                  visible: root.service && root.service.currentAlbumContextAvailable
                  hasCursor: root.cursorOn("footer", "album")
                  foreground: root.foreground
                  HoverHandler {
                    id: currentAlbumHover
                    onHoveredChanged: if (hovered)
                      root.setPanelCursor("footer", "album")
                  }
                  PanelToolTip {
                    visible: currentAlbumHover.hovered
                    text: root.shortcutHint("Open album", "Ctrl+Shift+B")
                  }

                  ArtistLinks {
                    id: currentAlbumLinks
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: currentAlbumHint.reservedRight
                    anchors.verticalCenter: parent.verticalCenter
                    artists: []
                    fallbackText: root.service ? root.service.album : ""
                    fallbackClickable: visible
                    color: root.accent
                    accent: root.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    onFallbackRequested: root.openCurrentAlbum()
                  }

                  KeyHint {
                    id: currentAlbumHint
                    region: "footer"
                    action: "album"
                    sequences: ["Ctrl+Shift+B"]
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                z: 20
                enabled: root.service && !!root.service.currentTrackItem
                onClicked: root.openNowPlayingContext()
              }
            }

            Column {
              id: transport
              width: Math.max(120, parent.width - nowPlaying.width - outputControls.width - parent.spacing * 2)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Style.space(3)

                TransportButton {
                  glyphText: "󰒟"
                  foreground: root.foreground
                  selected: root.service && root.service.shuffle
                  hasCursor: root.cursorOn("footer", "shuffle")
                  tooltipText: root.shortcutHint("Shuffle", "Ctrl+S")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.setShuffle(!root.service.shuffle)
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "shuffle")
                  }
                  KeyHint { region: "footer"; action: "shuffle"; sequences: ["Ctrl+S"] }
                }
                TransportButton {
                  glyphText: "󰒮"
                  foreground: root.foreground
                  hasCursor: root.cursorOn("footer", "previous")
                  tooltipText: root.shortcutHint("Previous", "Ctrl+Left")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.previous()
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "previous")
                  }
                  KeyHint { region: "footer"; action: "previous"; sequences: ["Ctrl+Left"] }
                }
                TransportButton {
                  glyphText: root.service && root.service.playing ? "󰏤" : "󰐊"
                  glyphSize: Style.font.iconLarge
                  foreground: root.foreground
                  selected: root.service && root.service.playing
                  hasCursor: root.cursorOn("footer", "play")
                  tooltipText: root.shortcutHint(
                    root.service && root.service.playing ? "Pause" : "Play", "Space")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.togglePlayback()
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "play")
                  }
                  KeyHint { region: "footer"; action: "play"; sequences: ["Space"] }
                }
                TransportButton {
                  glyphText: "󰒭"
                  foreground: root.foreground
                  hasCursor: root.cursorOn("footer", "next")
                  tooltipText: root.shortcutHint("Next", "Ctrl+Right")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.next()
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "next")
                  }
                  KeyHint { region: "footer"; action: "next"; sequences: ["Ctrl+Right"] }
                }
                TransportButton {
                  glyphText: root.service && root.service.repeatMode === "track" ? "󰑘" : "󰑖"
                  foreground: root.foreground
                  selected: root.service && root.service.repeatMode !== "off"
                  hasCursor: root.cursorOn("footer", "repeat")
                  tooltipText: root.shortcutHint("Repeat: "
                    + Api.repeatModeLabel(root.service
                      ? root.service.repeatMode : "off"), "Ctrl+R")
                  enabled: root.service && root.service.playbackControllable
                  onClicked: if (root.service) root.service.cycleRepeat()
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "repeat")
                  }
                  KeyHint { region: "footer"; action: "repeat"; sequences: ["Ctrl+R"] }
                }
                TransportButton {
                  glyphText: "󰎈"
                  foreground: root.foreground
                  hasCursor: root.cursorOn("footer", "lyrics")
                  tooltipText: root.shortcutHint("Open lyrics in Omasing",
                    "Ctrl+Shift+L")
                  enabled: root.service && root.service.lyricsAvailable
                  onClicked: root.openLyrics()
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "lyrics")
                  }
                  KeyHint { region: "footer"; action: "lyrics"; sequences: ["Ctrl+Shift+L"] }
                }
              }

              Row {
                width: parent.width
                spacing: Style.space(6)

                Text {
                  id: positionFooterTime
                  anchors.verticalCenter: parent.verticalCenter
                  text: Api.millisecondsToClock((root.service ? root.service.positionSeconds : 0) * 1000)
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                CursorSurface {
                  id: seekCursor
                  width: Math.max(30, parent.width - positionFooterTime.implicitWidth
                    - durationFooterTime.implicitWidth - Style.space(12))
                  height: positionSlider.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter
                  hasCursor: root.cursorOn("footer", "seek")
                  foreground: root.foreground
                  HoverHandler {
                    onHoveredChanged: if (hovered) root.setPanelCursor("footer", "seek")
                  }

                PlaybackSlider {
                  id: positionSlider
                  anchors.fill: parent
                  bar: root.panelBar
                  minimum: 0
                  maximum: Math.max(1, root.service ? root.service.lengthSeconds : 1)
                  step: 5
                  sourceValue: root.service ? root.service.positionSeconds : 0
                  sourcePending: root.service && root.service.pendingRemoteSeek !== null
                  acknowledgeTolerance: 2
                  contextKey: root.service
                    ? root.service.currentUri + "|" + root.service.playbackDeviceName : ""
                  onCommitted: function(value) {
                    if (root.service) root.service.seekSeconds(value)
                  }

                  HoverHandler { id: positionSliderHover }
                  PanelToolTip {
                    visible: positionSliderHover.hovered
                    text: "Seek 10 seconds · Shift+Left / Shift+Right"
                  }
                  KeyHint {
                    region: "footer"
                    action: "seek"
                    sequences: ["Shift+Left", "Shift+Right"]
                    active: root.shortcutHintsActive && root.service
                      && root.service.playbackControllable
                  }
                }
                }

                Text {
                  id: durationFooterTime
                  anchors.verticalCenter: parent.verticalCenter
                  text: Api.millisecondsToClock((root.service ? root.service.lengthSeconds : 0) * 1000)
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Column {
              id: outputControls
              width: Math.max(Style.space(128), Math.min(Style.space(170), playerRow.width * 0.22))
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Row {
                width: parent.width
                spacing: Style.space(5)

                Button {
                  iconText: "󰋋"
                  foreground: root.foreground
                  hasCursor: root.cursorOn("footer", "devices")
                  tooltipText: root.shortcutHint("Devices", "Alt+Shift+D")
                  onClicked: root.chooseTab("devices")
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "devices")
                  }
                  KeyHint { region: "footer"; action: "devices"; sequences: ["Alt+Shift+D"] }
                }

                Button {
                  iconText: "󰔛"
                  foreground: root.foreground
                  selected: root.service && root.service.sleepActive
                  hasCursor: root.cursorOn("footer", "sleep")
                  tooltipText: root.service ? root.service.sleepStatusText() : "Sleep timer"
                  onClicked: sleepPopup.open()
                  onHovered: function(on) {
                    if (on) root.setPanelCursor("footer", "sleep")
                  }
                  KeyHint { region: "footer"; action: "sleep" }
                }

                CursorSurface {
                  width: Math.max(35, parent.width - Style.space(74))
                  height: volumeSlider.implicitHeight
                  anchors.verticalCenter: parent.verticalCenter
                  hasCursor: root.cursorOn("footer", "volume")
                  foreground: root.foreground
                  HoverHandler {
                    onHoveredChanged: if (hovered) root.setPanelCursor("footer", "volume")
                  }

                PlaybackSlider {
                  id: volumeSlider
                  anchors.fill: parent
                  enabled: root.service && root.service.volumeSupported
                  bar: root.panelBar
                  minimum: 0
                  maximum: 1
                  step: 0.05
                  sourceValue: root.service ? root.service.volume : 0
                  sourcePending: root.service && root.service.volumePending
                  contextKey: root.service ? root.service.playbackDeviceName : ""
                  liveCommit: true
                  onCommitted: function(value, live) {
                    root.setPanelVolume(value, live)
                  }
                  onRightClicked: root.toggleMute()

                  HoverHandler { id: volumeSliderHover }
                  PanelToolTip {
                    visible: volumeSliderHover.hovered
                    text: "Volume · Ctrl+Up / Ctrl+Down · M to mute"
                  }
                  KeyHint {
                    region: "footer"
                    action: "volume"
                    sequences: ["M", "Ctrl+Up", "Ctrl+Down"]
                    active: root.shortcutHintsActive && root.service
                      && root.service.volumeSupported
                  }
                }
                }
              }

              Row {
                width: parent.width
                layoutDirection: Qt.RightToLeft
                spacing: Style.space(4)
                visible: root.service && root.service.playbackDeviceName !== ""

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.service ? root.service.playbackDeviceName : ""
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  elide: Text.ElideRight
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "󰦧"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }
        }
      }
    }
  }

  ShortcutModifiers {
    id: shortcutModifiers
  }

  Timer {
    id: unifiedSearchDelay
    interval: Api.SEARCH_DEBOUNCE_MS
    repeat: false
    onTriggered: root.runUnifiedSearch()
  }

  Timer {
    id: escapeCloseTimer
    interval: 1500
    repeat: false
    onTriggered: root.escapeCloseArmed = false
  }

  Timer {
    interval: 1000
    repeat: true
    running: root.opened && root.service && root.service.playing
    onTriggered: root.service.refreshPosition()
  }

  Component {
    id: homePage

    HomePage {
      panel: root
    }
  }

  Component {
    id: discoverPage

    DiscoverPage {
      panel: root
    }
  }

  Component {
    id: detailPage

    DetailPage {
      panel: root
    }
  }

  Component {
    id: searchPage

    SearchPage {
      panel: root
    }
  }

  Component {
    id: libraryPage

    LibraryPage {
      panel: root
    }
  }

  Component {
    id: playlistsPage

    PlaylistsPage {
      panel: root
    }
  }

  Component {
    id: queuePage

    QueuePage {
      panel: root
    }
  }

  Component {
    id: devicesPage

    DevicesPage {
      panel: root
    }
  }

  Component {
    id: loginPage

    LoginPage {
      panel: root
    }
  }

  Component {
    id: setupPage

    SettingsPage {
      panel: root
    }
  }
}
