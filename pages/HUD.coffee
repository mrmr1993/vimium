showText = (data) ->
  hud = document.getElementById "hud"
  hud.innerText = data.text

showUpgradeNotification = (data) ->
  hud = document.getElementById "hud"
  hud.innerHTML = "Vimium has been upgraded to #{data.version}. See
    <a class='vimiumReset' target='_blank'
    href='https://github.com/philc/vimium#release-notes'>
    what's new</a>.<a class='vimiumReset close-button' href='#'>&times;</a>"

  updateLinkClicked = ->
    UIComponentServer.postMessage name: "hideUpgradeNotification"
    chrome.runtime.sendMessage name: "upgradeNotificationClosed"

  links = hud.getElementsByTagName("a")
  links[0].addEventListener "click", updateLinkClicked, false
  links[1].addEventListener "click", (event) ->
    event.preventDefault()
    updateLinkClicked()
  , false

# This implements a find-mode query history (using the "findModeRawQueryList" setting) as a list of raw
# queries, most recent first.
FindModeHistory =
  getQuery: (index = 0) ->
    @migration()
    recentQueries = settings.get "findModeRawQueryList"
    if index < recentQueries.length then recentQueries[index] else ""

  recordQuery: (query) ->
    @migration()
    if 0 < query.length
      recentQueries = settings.get "findModeRawQueryList"
      settings.set "findModeRawQueryList", ([ query ].concat recentQueries.filter (q) -> q != query)[0..50]

  # Migration (from 1.49, 2015/2/1).
  # Legacy setting: findModeRawQuery (a string).
  # New setting: findModeRawQueryList (a list of strings).
  migration: ->
    unless settings.get "findModeRawQueryList"
      rawQuery = settings.get "findModeRawQuery"
      settings.set "findModeRawQueryList", (if rawQuery then [ rawQuery ] else [])

enterFindMode = (data) ->
  hud = document.getElementById "hud"
  hud.innerText = "/"

  inputElement = document.createElement "span"
  inputElement.contentEditable = "plaintext-only"
  inputElement.id = "hud-find-input"
  hud.appendChild inputElement

  inputElement.addEventListener "input", (event) ->
    # Strip newlines in case the user has pasted some.
    UIComponentServer.postMessage name: "search", query: inputElement.innerText.replace(/\r\n/g, "")

  # Find-mode history state.
  historyIndex = -1
  partialQuery = ""

  document.addEventListener "keydown", (event) ->
    chrome.storage.local.get "findModeRawQueryList", (items) -> console.log items
    # Three keys for exiting find mode...
    if KeyboardUtils.isEscape event
      eventType = "esc"
    else if event.keyCode in [ keyCodes.backspace, keyCodes.deleteKey ]
      return unless inputElement.innerText.replace(/\r\n/g, "").length == 0
      eventType = "del"
    else if event.keyCode == keyCodes.enter
      eventType = "enter"

    # Two keys for manipulating the find-mode history.
    else if event.keyCode == keyCodes.upArrow
      if rawQuery = FindModeHistory.getQuery historyIndex + 1
        historyIndex += 1
        partialQuery = findModeQuery.rawQuery if historyIndex == 0
        updateQueryForFindMode rawQuery
      DomUtils.suppressEvent event
      return false
    else if event.keyCode == keyCodes.downArrow
      historyIndex = Math.max -1, historyIndex - 1
      rawQuery = if 0 <= historyIndex then FindModeHistory.getQuery historyIndex else partialQuery
      updateQueryForFindMode rawQuery
      DomUtils.suppressEvent event
      return false

    else
      return true # Don't handle this key.

    DomUtils.suppressEvent event
    UIComponentServer.postMessage
      name: "hideFindMode"
      type: eventType
      query: inputElement.innerText.replace /\r\n/g, ""
    inputElement.blur()

  inputElement.focus()

updateMatchesCount = (data) ->
  inputElement = document.getElementById "hud-find-input"
  return unless inputElement? # Don't do anything if we're not in find mode.

  hud = document.getElementById "hud"
  nodeAfter = inputElement.nextSibling
  countText = " (#{if data.count == 0 then "No" else data.count} matches)"

  # Replace the old count (if there was one) with the new one.
  hud.insertBefore document.createTextNode(countText), nodeAfter
  nodeAfter?.remove()

handlers =
  show: showText
  upgrade: showUpgradeNotification
  find: enterFindMode
  updateMatchesCount: updateMatchesCount

UIComponentServer.registerHandler (event) ->
  {data} = event
  handlers[data.name]? data
