root = exports ? window

# TabRecency associates a logical timestamp with each tab id.  These are used to provide an initial
# recency-based ordering in the tabs vomnibar (which allows jumping quickly between recently-visited tabs).
class TabRecency
  timestamp: 1
  current: -1
  cache: {}
  lastVisited: null
  lastVisitedTime: null
  timeDelta: 500 # Milliseconds.

  constructor: ->
    chrome.tabs.onActivated.addListener (activeInfo) => @register activeInfo.tabId
    chrome.tabs.onRemoved.addListener (tabId) => @deregister tabId

    chrome.tabs.onReplaced.addListener (addedTabId, removedTabId) =>
      @deregister removedTabId
      @register addedTabId

    chrome.windows.onFocusChanged.addListener (wnd) =>
      if wnd != chrome.windows.WINDOW_ID_NONE
        chrome.tabs.query {windowId: wnd, active: true}, (tabs) =>
          @register tabs[0].id if tabs[0]

  register: (tabId) ->
    currentTime = new Date()
    # Register tabId if it has been visited for at least @timeDelta ms.  Tabs which are visited only for a
    # very-short time (e.g. those passed through with `5J`) aren't registered as visited at all.
    if @lastVisitedTime? and @timeDelta <= currentTime - @lastVisitedTime
      @cache[@lastVisited] = ++@timestamp

    @current = @lastVisited = tabId
    @lastVisitedTime = currentTime

  deregister: (tabId) ->
    if tabId == @lastVisited
      # Ensure we don't register this tab, since it's going away.
      @lastVisited = @lastVisitedTime = null
    delete @cache[tabId]

  # Recently-visited tabs get a higher score (except the current tab, which gets a low score).
  recencyScore: (tabId) ->
    @cache[tabId] ||= 1
    if tabId == @current then 0.0 else @cache[tabId] / @timestamp

  # Returns a list of tab Ids sorted by recency, most recent tab first.
  getTabsByRecency: ->
    tabIds = (tId for own tId of @cache)
    tabIds.sort (a,b) => @cache[b] - @cache[a]
    tabIds.map (tId) -> parseInt tId

BgUtils =
  tabRecency: new TabRecency()

  # Log messages to the extension's logging page, but only if that page is open.
  log: do ->
    loggingPageUrl = chrome.runtime.getURL "pages/logging.html"
    console.log "Vimium logging URL:\n  #{loggingPageUrl}" if loggingPageUrl? # Do not output URL for tests.
    # For development, it's sometimes useful to automatically launch the logging page on reload.
    chrome.windows.create url: loggingPageUrl, focused: false if localStorage.autoLaunchLoggingPage
    (message, sender = null) ->
      for viewWindow in chrome.extension.getViews {type: "tab"}
        if viewWindow.location.pathname == "/pages/logging.html"
          # Don't log messages from the logging page itself.  We do this check late because most of the time
          # it's not needed.
          if sender?.url != loggingPageUrl
            date = new Date
            [hours, minutes, seconds, milliseconds] =
              [date.getHours(), date.getMinutes(), date.getSeconds(), date.getMilliseconds()]
            minutes = "0" + minutes if minutes < 10
            seconds = "0" + seconds if seconds < 10
            milliseconds = "00" + milliseconds if milliseconds < 10
            milliseconds = "0" + milliseconds if milliseconds < 100
            dateString = "#{hours}:#{minutes}:#{seconds}.#{milliseconds}"
            logElement = viewWindow.document.getElementById "log-text"
            logElement.value += "#{dateString}: #{message}\n"
            logElement.scrollTop = 2000000000

root.BgUtils = BgUtils
