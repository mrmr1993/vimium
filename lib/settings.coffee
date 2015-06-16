
Settings =
  storage: chrome.storage.sync
  cache: {}
  isLoaded: false
  onLoadedCallbacks: []

  init: ->
    if Utils.isExtensionPage()
      # On extension pages, we use localStorage (or a copy of it) as the cache.
      @cache = if Utils.isBackgroundPage() then localStorage else extend {}, localStorage
      @onLoaded()

    # We store settings in various storage areas (always JSONified).  They take priority (lowest to highest):
    # localStorage, chrome.storage.local, chrome.storage.sync.
    chrome.storage.local.get null, (localItems) =>
      @storage.get null, (syncedItems) =>
        unless chrome.runtime.lastError
          # Items from synced storage take priority.
          @handleUpdateFromChromeStorage key, value for own key, value of extend localItems, syncedItems

        chrome.storage.onChanged.addListener (changes, area) =>
          @propagateChangesFromChromeStorage changes, area if area == "sync"

        @onLoaded()
        @activateChromeStorageLocalMaintainer()

  # Called after @cache has been initialized.  On extension pages, this will be called twice, but that does
  # not matter because it's idempotent.
  onLoaded: ->
    @isLoaded = true
    callback() while callback = @onLoadedCallbacks.pop()

  shouldSyncKey: (key) ->
    (key of @defaults) and key not in [ "settingsVersion", "previousVersion" ]

  propagateChangesFromChromeStorage: (changes) ->
    @handleUpdateFromChromeStorage key, change?.newValue for own key, change of changes

  handleUpdateFromChromeStorage: (key, value) ->
    # Note: value here is either null or a JSONified string.  Therefore, even falsy settings values (like
    # false, 0 or "") are truthy here.  Only null is falsy.
    if @shouldSyncKey key
      unless value and key of @cache and @cache[key] == value
        defaultValue = @defaults[key]
        defaultValueJSON = JSON.stringify defaultValue

        if value and value != defaultValueJSON
          # Key/value has been changed to a non-default value.
          @cache[key] = value
          @performPostUpdateHook key, JSON.parse value
        else
          # The key has been reset to its default value.
          delete @cache[key] if key of @cache
          @performPostUpdateHook key, defaultValue

  get: (key) ->
    console.log "WARNING: Settings have not loaded yet; using the default value for #{key}." unless @isLoaded
    if key of @cache and @cache[key]? then JSON.parse @cache[key] else @defaults[key]

  set: (key, value) ->
    # Don't store the value if it is equal to the default, so we can change the defaults in the future.
    if @isDefaultValue key
      @clear key
    else
      jsonValue = JSON.stringify value
      @cache[key] = jsonValue
      if @shouldSyncKey key
        setting = {}; setting[key] = jsonValue
        @storage.set setting
      @performPostUpdateHook key, value

  clear: (key) ->
    delete @cache[key] if @has key
    @storage.remove key if @shouldSyncKey key
    @performPostUpdateHook key, @get key

  has: (key) -> key of @cache

  use: (key, callback) ->
    invokeCallback = => callback @get key
    if @isLoaded then invokeCallback() else @onLoadedCallbacks.push invokeCallback

  isDefaultValue: (key) ->
    JSON.stringify(@get key) == JSON.stringify @defaults[key]

  # For settings which require action when their value changes, add hooks to this object.
  postUpdateHooks: {}
  addPostUpdateHook: (key, callback) -> (@postUpdateHooks[key] ?= []).push callback
  performPostUpdateHook: (key, value) ->
    callback value for callback in (@postUpdateHooks[key] ? [])

  # Default values for all settings.
  defaults:
    scrollStepSize: 60
    smoothScroll: true
    keyMappings: "# Insert your preferred key mappings here."
    linkHintCharacters: "sadfjklewcmpgh"
    linkHintNumbers: "0123456789"
    filterLinkHints: false
    hideHud: false
    userDefinedLinkHintCss:
      """
      div > .vimiumHintMarker {
      /* linkhint boxes */
      background: -webkit-gradient(linear, left top, left bottom, color-stop(0%,#FFF785),
        color-stop(100%,#FFC542));
      border: 1px solid #E3BE23;
      }

      div > .vimiumHintMarker span {
      /* linkhint text */
      color: black;
      font-weight: bold;
      font-size: 12px;
      }

      div > .vimiumHintMarker > .matchingCharacter {
      }
      """
    # Default exclusion rules.
    exclusionRules:
      [
        # Disable Vimium on Gmail.
        { pattern: "https?://mail.google.com/*", passKeys: "" }
      ]

    # NOTE: If a page contains both a single angle-bracket link and a double angle-bracket link, then in
    # most cases the single bracket link will be "prev/next page" and the double bracket link will be
    # "first/last page", so we put the single bracket first in the pattern string so that it gets searched
    # for first.

    # "\bprev\b,\bprevious\b,\bback\b,<,←,«,≪,<<"
    previousPatterns: "prev,previous,back,<,\u2190,\xab,\u226a,<<"
    # "\bnext\b,\bmore\b,>,→,»,≫,>>"
    nextPatterns: "next,more,>,\u2192,\xbb,\u226b,>>"
    # default/fall back search engine
    searchUrl: "https://www.google.com/search?q="
    # put in an example search engine
    searchEngines:
      """
      w: http://www.wikipedia.org/w/index.php?title=Special:Search&search=%s Wikipedia

      # More examples.
      #
      # (Vimium supports search completion Wikipedia, as
      # above, and for these.)
      #
      # g: http://www.google.com/search?q=%s Google
      # l: http://www.google.com/search?q=%s&btnI I'm feeling lucky...
      # y: http://www.youtube.com/results?search_query=%s Youtube
      # gm: https://www.google.com/maps?q=%s Google maps
      # b: https://www.bing.com/search?q=%s Bing
      # d: https://duckduckgo.com/?q=%s DuckDuckGo
      # az: http://www.amazon.com/s/?field-keywords=%s Amazon
      """
    newTabUrl: "chrome://newtab"
    grabBackFocus: false
    regexFindMode: false

    settingsVersion: Utils.getCurrentVersion()
    helpDialog_showAdvancedCommands: false

  # Ideally, each setting is either set to its default value and not in synced storage, or set to some other
  # value and in synced storage.  However, settings which have not been changed since synced storage was
  # introduced may have a non-default value and nevertheless *not* be in synced storage.  We use
  # chrome.storage.local to push such settings values out to content pages.
  activateChromeStorageLocalMaintainer: ->
    if Utils.isBackgroundPage()
      for own key, value of localStorage
        if @shouldSyncKey(key) and not @isDefaultValue key
          # This setting should be synced, and it's not set to its default value.
          do (key, value) =>
            @storage.get key, (items) =>
              unless chrome.runtime.lastError or items[key]
                # This key should be synced, it's not set to its default value, AND it's not in synced
                # storage.  We set its value in chrome.storage.local; content pages will have access to it
                # there.
                obj = {}; obj[key] = JSON.stringify value
                chrome.storage.local.set obj

                postUpdateHook = (value) =>
                  # The setting is now either restored to its default value, or it's in synced storage.  We
                  # no longer need it in chrome.storage.local.
                  chrome.storage.local.remove key
                  # Deactivate this post-update hook; its done its job and we don't need it any more.
                  postUpdateHook = ->
                  if @isDefaultValue key
                    # The setting has been reset to its default value. This will not cause a change to synced
                    # storage, so the update will not (otherwise) be propagated to active tabs.  We need to
                    # force an update in synced storage (in fact, we force two updates).
                    obj = {}; obj[key] = JSON.stringify @defaults[key]
                    @storage.set obj, => @storage.remove key

                @addPostUpdateHook key, (value) -> postUpdateHook value

Settings.init()

# Perform migration from old settings versions, if this is the background page.
if Utils.isBackgroundPage()

  # We use settingsVersion to coordinate any necessary schema changes.
  if Utils.compareVersions("1.42", Settings.get("settingsVersion")) != -1
    Settings.set("scrollStepSize", parseFloat Settings.get("scrollStepSize"))
  Settings.set("settingsVersion", Utils.getCurrentVersion())

  # Migration (after 1.49, 2015/2/1).
  # Legacy setting: findModeRawQuery (a string).
  # New setting: findModeRawQueryList (a list of strings), now stored in chrome.storage.local (not localStorage).
  chrome.storage.local.get "findModeRawQueryList", (items) ->
    unless chrome.runtime.lastError or items.findModeRawQueryList
      rawQuery = Settings.get "findModeRawQuery"
      chrome.storage.local.set findModeRawQueryList: (if rawQuery then [ rawQuery ] else [])

root = exports ? window
root.Settings = Settings
