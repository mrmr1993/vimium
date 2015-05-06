#
# This controls the contents of the Vomnibar iframe. We use an iframe to avoid changing the selection on the
# page (useful for bookmarklets), ensure that the Vomnibar style is unaffected by the page, and simplify key
# handling in vimium_frontend.coffee
#
Vomnibar =
  vomnibarUI: null # the dialog instance for this window
  getUI: -> @vomnibarUI
  completers: {}

  getCompleter: (name) ->
    if (!(name of @completers))
      @completers[name] = new BackgroundCompleter(name)
    @completers[name]

  #
  # Activate the Vomnibox.
  #
  activate: (userOptions) ->
    options =
      completer: "omni"
      query: ""
      newTab: false
      selectFirst: false
    extend options, userOptions

    options.refreshInterval =
      if options.completer == "omni" then 125 else 0

    completer = @getCompleter(options.completer)
    @vomnibarUI ?= new VomnibarUI()
    completer.refresh()
    @vomnibarUI.setInitialSelectionValue(if options.selectFirst then 0 else -1)
    @vomnibarUI.setCompleter(completer)
    @vomnibarUI.setRefreshInterval(options.refreshInterval)
    @vomnibarUI.setForceNewTab(options.newTab)
    @vomnibarUI.setQuery(options.query)
    @vomnibarUI.update()

  hide: -> @vomnibarUI?.hide()
  onHidden: -> @vomnibarUI?.onHidden()

class VomnibarUI
  constructor: ->
    @refreshInterval = 0
    @postHideCallback = null
    @initDom()

  setQuery: (query) -> @input.value = query

  setInitialSelectionValue: (initialSelectionValue) ->
    @initialSelectionValue = initialSelectionValue

  setCompleter: (completer) ->
    @completer = completer
    @reset()
    @update(true)

  setRefreshInterval: (refreshInterval) -> @refreshInterval = refreshInterval

  setForceNewTab: (forceNewTab) -> @forceNewTab = forceNewTab

  # The sequence of events when the vomnibar is hidden is as follows:
  # 1. Post a "hide" message to the host page.
  # 2. The host page hides the vomnibar.
  # 3. When that page receives the focus, and it posts back a "hidden" message.
  # 3. Only once the "hidden" message is received here is any required action  invoked (in onHidden).
  # This ensures that the vomnibar is actually hidden before any new tab is created, and avoids flicker after
  # opening a link in a new tab then returning to the original tab (see #1485).
  hide: (@postHideCallback = null) ->
    UIComponentServer.postMessage "hide"
    @reset()

  onHidden: ->
    @postHideCallback?()
    @postHideCallback = null

  reset: ->
    @completionList.style.display = ""
    @input.value = ""
    @updateTimer = null
    @completions = []
    @previousAutoSelect = null
    @previousInputValue = null
    @selection = @initialSelectionValue
    @previousText = null

  updateSelection: ->
    # We retain global state here (previousAutoSelect) to tell if a search item (for which autoSelect is set)
    # has just appeared or disappeared. If that happens, we set @selection to 0 or -1.
    if 0 < @completions.length
      @selection = 0 if @completions[0].autoSelect and not @previousAutoSelect
      @selection = -1 if @previousAutoSelect and not @completions[0].autoSelect
      @previousAutoSelect = @completions[0].autoSelect
    else
      @previousAutoSelect = null

    # For suggestions from search-engine completion, we copy the suggested text into the input when selected,
    # and revert when not.  This allows the user to select a suggestion and then continue typing.
    if 0 <= @selection and @completions[@selection].insertText?
      @previousInputValue ?= @input.value
      @input.value = @completions[@selection].insertText
    else if @previousInputValue?
        @input.value = @previousInputValue
        @previousInputValue = null

    # Highlight the the selected entry, and only the selected entry.
    for i in [0...@completionList.children.length]
      @completionList.children[i].className = (if i == @selection then "vomnibarSelected" else "")

  #
  # Returns the user's action ("up", "down", "enter", "dismiss" or null) based on their keypress.
  # We support the arrow keys and other shortcuts for moving, so this method hides that complexity.
  #
  actionFromKeyEvent: (event) ->
    key = KeyboardUtils.getKeyChar(event)
    if (KeyboardUtils.isEscape(event))
      return "dismiss"
    else if (key == "up" ||
        (event.shiftKey && event.keyCode == keyCodes.tab) ||
        (event.ctrlKey && (key == "k" || key == "p")))
      return "up"
    else if (key == "down" ||
        (event.keyCode == keyCodes.tab && !event.shiftKey) ||
        (event.ctrlKey && (key == "j" || key == "n")))
      return "down"
    else if (event.keyCode == keyCodes.enter)
      return "enter"

  onKeydown: (event) =>
    action = @actionFromKeyEvent(event)
    return true unless action # pass through

    openInNewTab = @forceNewTab ||
      (event.shiftKey || event.ctrlKey || KeyboardUtils.isPrimaryModifierKey(event))
    if (action == "dismiss")
      @hide()
    else if (action == "up")
      @selection -= 1
      @selection = @completions.length - 1 if @selection < @initialSelectionValue
      @updateSelection()
    else if (action == "down")
      @selection += 1
      @selection = @initialSelectionValue if @selection == @completions.length
      @updateSelection()
    else if (action == "enter")
      # If they type something and hit enter without selecting a completion from our list of suggestions,
      # try to open their query as a URL directly. If it doesn't look like a URL, we will search using
      # google.
      if (@selection == -1)
        query = @input.value.trim()
        # <Enter> on an empty vomnibar is a no-op.
        return unless 0 < query.length
        @hide ->
          chrome.runtime.sendMessage
            handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
            url: query
      else
        completion = @completions[@selection]
        @update true, =>
          # Shift+Enter will open the result in a new tab instead of the current tab.
          @hide -> completion.performAction openInNewTab

    # It seems like we have to manually suppress the event here and still return true.
    event.stopImmediatePropagation()
    event.preventDefault()
    true

  updateCompletions: (callback = null) ->
    @completer.filter @input.value.trim(), (@completions) =>
      @populateUiWithCompletions @completions
      callback?()

  populateUiWithCompletions: (completions) ->
    # update completion list with the new data
    @completionList.innerHTML = completions.map((completion) -> "<li>#{completion.html}</li>").join("")
    @completionList.style.display = if completions.length > 0 then "block" else ""
    @selection = Math.min completions.length - 1, Math.max @initialSelectionValue, @selection
    @updateSelection()

  updateOnInput: =>
    @completer.userIsTyping()
    # If the user types, then don't reset any previous text, and re-enable auto-select.
    if @previousInputValue?
      @previousInputValue = null
      @previousAutoSelect = null
      @selection = -1
    @update()

  update: (updateSynchronously = false, callback = null) =>
    if updateSynchronously
      # Cancel any scheduled update.
      if @updateTimer?
        window.clearTimeout @updateTimer
        @updateTimer = null
      @updateCompletions callback
    else if not @updateTimer?
      # Update asynchronously for better user experience and to take some load off the CPU (not every
      # keystroke will cause a dedicated update)
      @updateTimer = Utils.setTimeout @refreshInterval, =>
        @updateTimer = null
        @updateCompletions callback

    @input.focus()

  initDom: ->
    @box = document.getElementById("vomnibar")

    @input = @box.querySelector("input")
    @input.addEventListener "input", @updateOnInput
    @input.addEventListener "keydown", @onKeydown
    @completionList = @box.querySelector("ul")
    @completionList.style.display = ""

    window.addEventListener "focus", => @input.focus()
    # A click in the vomnibar itself refocuses the input.
    @box.addEventListener "click", (event) =>
      @input.focus()
      event.stopImmediatePropagation()
    # A click anywhere else hides the vomnibar.
    document.body.addEventListener "click", => @hide()

#
# Sends requests to a Vomnibox completer on the background page.
#
class BackgroundCompleter
  # name is background-page completer to connect to: "omni", "tabs", or "bookmarks".
  constructor: (@name) ->
    @messageId = null
    @port = chrome.runtime.connect name: "completions"
    @port.onMessage.addListener handler = @messageHandler

  messageHandler: (msg) =>
    # We ignore messages which arrive too late.
    if msg.id == @messageId
      # The result objects coming from the background page will be of the form:
      #   { html: "", type: "", url: "" }
      # type will be one of [tab, bookmark, history, domain].
      results = msg.results.map (result) =>
        functionToCall = if  result.type == "tab"
          @completionActions.switchToTab.curry result.tabId
        else
          @completionActions.navigateToUrl.curry result.url
        result.performAction = functionToCall
        result
      @mostRecentCallback results

  filter: (query, @mostRecentCallback) ->
    @messageId = Utils.createUniqueId()
    @port.postMessage name: @name, handler: "filter", id: @messageId, query: query

  refresh: ->
    @port.postMessage name: @name, handler: "refreshCompleter"

  userIsTyping: ->
    @port.postMessage name: @name, handler: "userIsTyping"

  # These are the actions we can perform when the user selects a result in the Vomnibox.
  completionActions:
    navigateToUrl: (url, openInNewTab) ->
      # If the URL is a bookmarklet prefixed with javascript:, we shouldn't open that in a new tab.
      openInNewTab = false if url.startsWith("javascript:")
      chrome.runtime.sendMessage(
        handler: if openInNewTab then "openUrlInNewTab" else "openUrlInCurrentTab"
        url: url,
        selected: openInNewTab)

    switchToTab: (tabId) -> chrome.runtime.sendMessage({ handler: "selectSpecificTab", id: tabId })

UIComponentServer.registerHandler (event) ->
  switch event.data
    when "hide" then Vomnibar.hide()
    when "hidden" then Vomnibar.onHidden()
    else Vomnibar.activate event.data

root = exports ? window
root.Vomnibar = Vomnibar
