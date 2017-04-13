findMode = null

# Set the input element's text, and move the cursor to the end.
setTextInInputElement = (inputElement, text) ->
  inputElement.textContent = text
  # Move the cursor to the end.  Based on one of the solutions here:
  # http://stackoverflow.com/questions/1125292/how-to-move-cursor-to-end-of-contenteditable-entity
  range = document.createRange()
  range.selectNodeContents inputElement
  range.collapse false
  selection = window.getSelection()
  selection.removeAllRanges()
  selection.addRange range

document.addEventListener "keydown", (event) ->
  inputElement = document.getElementById "hud-find-input"
  return unless inputElement? # Don't do anything if we're not in find mode.

  if (KeyboardUtils.isBackspace(event) and inputElement.textContent.length == 0) or
     event.key == "Enter" or KeyboardUtils.isEscape event

    UIComponentServer.postMessage
      name: "hideFindMode"
      exitEventIsEnter: event.key == "Enter"
      exitEventIsEscape: KeyboardUtils.isEscape event

    document.getElementById("hud-find-input").blur() # Blur the input so it doesn't steal focus.

  else if event.key == "ArrowUp"
    if rawQuery = FindModeHistory.getQuery findMode.historyIndex + 1
      findMode.historyIndex += 1
      findMode.partialQuery = findMode.rawQuery if findMode.historyIndex == 0
      setTextInInputElement inputElement, rawQuery
      findMode.executeQuery()
  else if event.key == "ArrowDown"
    findMode.historyIndex = Math.max -1, findMode.historyIndex - 1
    rawQuery = if 0 <= findMode.historyIndex then FindModeHistory.getQuery findMode.historyIndex else findMode.partialQuery
    setTextInInputElement inputElement, rawQuery
    findMode.executeQuery()
  else
    return

  DomUtils.suppressEvent event
  false

executeFindQuery = (event) ->
  # Replace \u00A0 (&nbsp;) with a normal space.
  findMode.rawQuery = event.target.textContent.replace "\u00A0", " "
  UIComponentServer.postMessage {name: "search", query: findMode.rawQuery}

handlers =
  show: (data) ->
    document.getElementById("hud").innerText = data.text

    document.getElementById("hud").style.display = ""
    document.getElementById("hud-find").style.display = "none" # Hide the find mode HUD.
  hidden: ->
    # We get a flicker when the HUD later becomes visible again (with new text) unless we reset its contents
    # here.
    document.getElementById("hud").innerText = ""
    document.getElementById("hud-find-input").textContent = ""
    document.getElementById("hud-match-count").textContent = ""

    document.getElementById("hud-find-input").blur() # Blur the input so it doesn't steal focus.

    document.getElementById("hud").style.display = "none"
    document.getElementById("hud-find").style.display = "none"

  showFindMode: (data) ->
    document.getElementById("hud-match-count").textContent = ""

    # Hide the normal HUD, show the find mode HUD.
    document.getElementById("hud").style.display = "none"
    document.getElementById("hud-find").style.display = ""

    inputElement = document.getElementById "hud-find-input"

    inputElement.addEventListener "input", executeFindQuery
    inputElement.focus()

    findMode =
      historyIndex: -1
      partialQuery: ""
      rawQuery: ""
      executeQuery: executeFindQuery

  updateMatchesCount: ({matchCount, showMatchText}) ->
    countElement = document.getElementById "hud-match-count"
    return unless countElement? # Don't do anything if we're not in find mode.

    countText = if matchCount > 0
      " (#{matchCount} Match#{if matchCount == 1 then "" else "es"})"
    else
      " (No matches)"
    countElement.textContent = if showMatchText then countText else ""

UIComponentServer.registerHandler ({data}) -> handlers[data.name ? data]? data
FindModeHistory.init()
