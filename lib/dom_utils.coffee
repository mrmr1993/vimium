DomUtils =
  #
  # Runs :callback if the DOM has loaded, otherwise runs it on load
  #
  documentReady: do ->
    loaded = false
    window.addEventListener("DOMContentLoaded", -> loaded = true)
    (callback) -> if loaded then callback() else window.addEventListener("DOMContentLoaded", callback)

  #
  # Adds a list of elements to a page.
  # Note that adding these nodes all at once (via the parent div) is significantly faster than one-by-one.
  #
  addElementList: (els, overlayOptions) ->
    parent = document.createElement("div")
    parent.id = overlayOptions.id if overlayOptions.id?
    parent.className = overlayOptions.className if overlayOptions.className?
    parent.appendChild(el) for el in els

    document.documentElement.appendChild(parent)
    parent

  #
  # Remove an element from its DOM tree.
  #
  removeElement: (el) -> el.parentNode.removeChild el

  #
  # Takes an array of XPath selectors, adds the necessary namespaces (currently only XHTML), and applies them
  # to the document root. The namespaceResolver in evaluateXPath should be kept in sync with the namespaces
  # here.
  #
  makeXPath: (elementArray) ->
    xpath = []
    for i of elementArray
      xpath.push("//" + elementArray[i], "//xhtml:" + elementArray[i])
    xpath.join(" | ")

  evaluateXPath: (xpath, resultType = XPathResult.ORDERED_NODE_SNAPSHOT_TYPE) ->
    namespaceResolver = (namespace) ->
      if (namespace == "xhtml") then "http://www.w3.org/1999/xhtml" else null
    document.evaluate(xpath, document.documentElement, namespaceResolver, resultType, null)

  #
  # Returns the first visible clientRect of an element if it exists. Otherwise it returns null.
  #
  getVisibleClientRect: (element) ->
    # Note: this call will be expensive if we modify the DOM in between calls.
    clientRects = ({
      top: clientRect.top, right: clientRect.right, bottom: clientRect.bottom, left: clientRect.left,
      width: clientRect.width, height: clientRect.height
    } for clientRect in element.getClientRects())

    for clientRect in clientRects
      if (clientRect.top < 0)
        clientRect.oldTop = clientRect.top
        clientRect.oldHeight = clientRect.height
        clientRect.height += clientRect.top
        clientRect.top = 0

      if (clientRect.left < 0)
        clientRect.oldLeft = clientRect.left
        clientRect.oldWidth = clientRect.width
        clientRect.width += clientRect.left
        clientRect.left = 0

      if (clientRect.top >= window.innerHeight - 4 || clientRect.left  >= window.innerWidth - 4)
        continue

      if (clientRect.width < 3 || clientRect.height < 3)
        continue

      # eliminate invisible elements (see test_harnesses/visibility_test.html)
      computedStyle = window.getComputedStyle(element, null)
      if (computedStyle.getPropertyValue('visibility') != 'visible' ||
          computedStyle.getPropertyValue('display') == 'none' ||
          computedStyle.getPropertyValue('opacity') == '0')
        continue

      return clientRect

    for clientRect in clientRects
      # If the link has zero dimensions, it may be wrapping visible
      # but floated elements. Check for this.
      if (clientRect.width == 0 || clientRect.height == 0)
        for child in element.children
          computedStyle = window.getComputedStyle(child, null)
          # Ignore child elements which are not floated and not absolutely positioned for parent elements with
          # zero width/height
          continue if (computedStyle.getPropertyValue('float') == 'none' &&
            computedStyle.getPropertyValue('position') != 'absolute')
          childClientRect = @getVisibleClientRect(child)
          continue if (childClientRect == null)
          return childClientRect
    null

  #
  # Selectable means the element has a text caret; this is not the same as "focusable".
  #
  isSelectable: (element) ->
    unselectableTypes = ["button", "checkbox", "color", "file", "hidden", "image", "radio", "reset"]
    (element.nodeName.toLowerCase() == "input" && unselectableTypes.indexOf(element.type) == -1) ||
        element.nodeName.toLowerCase() == "textarea"

  simulateSelect: (element) ->
    element.focus()
    # When focusing a textbox, put the selection caret at the end of the textbox's contents.
    # For some HTML5 input types (eg. date) we can't position the caret, so we wrap this with a try.
    try element.setSelectionRange(element.value.length, element.value.length)

  # For contentEditable elements, we need to explicitly set a caret in them to make sure they are activated.
  focusContentEditable: (element) ->
    range = document.createRange()
    if element.lastChild
      range.setStartAfter element.lastChild
      range.setEndAfter element.lastChild

    sel = window.getSelection()
    sel.removeAllRanges()
    sel.addRange range

    element.focus()

  # Detect contentEditable elements having focus via the current selection. This avoids issues with tracking
  # blur/focus events on badly behaved elements.
  # (See comment isInsertMode in content_scripts/vimium_frontend.coffee for more info.)
  isContentEditableFocused: ->
    {type: selType, anchorNode} = document.getSelection()
    return false unless anchorNode?
    # We need an element. If anchorNode is not an element (eg. a text node) then we take its parentElement.
    anchorElement = if "isContentEditable" of anchorNode then anchorNode else anchorNode.parentElement

    (selType == "Caret" or selType == "Range") and anchorElement.isContentEditable

  getFocusedContentEditable: ->
    {anchorNode} = document.getSelection()
    ceElement = if "isContentEditable" of anchorNode then anchorNode else anchorNode.parentElement

    return null unless ceElement.isContentEditable

    ceElement = ceElement.parentElement while ceElement.parentElement.isContentEditable
    ceElement

  simulateClick: (element, modifiers) ->
    modifiers ||= {}

    eventSequence = ["mouseover", "mousedown", "mouseup", "click"]
    for event in eventSequence
      mouseEvent = document.createEvent("MouseEvents")
      mouseEvent.initMouseEvent(event, true, true, window, 1, 0, 0, 0, 0, modifiers.ctrlKey, modifiers.altKey,
      modifiers.shiftKey, modifiers.metaKey, 0, null)
      # Debugging note: Firefox will not execute the element's default action if we dispatch this click event,
      # but Webkit will. Dispatching a click on an input box does not seem to focus it; we do that separately
      element.dispatchEvent(mouseEvent)

  # momentarily flash a rectangular border to give user some visual feedback
  flashRect: (rect) ->
    flashEl = document.createElement("div")
    flashEl.id = "vimiumFlash"
    flashEl.className = "vimiumReset"
    flashEl.style.left = rect.left + window.scrollX + "px"
    flashEl.style.top = rect.top  + window.scrollY  + "px"
    flashEl.style.width = rect.width + "px"
    flashEl.style.height = rect.height + "px"
    document.documentElement.appendChild(flashEl)
    setTimeout((-> DomUtils.removeElement flashEl), 400)

  suppressPropagation: (event) ->
    event.stopImmediatePropagation()

  suppressEvent: (event) ->
    event.preventDefault()
    @suppressPropagation(event)

  # The browser ignores our DomUtils.suppressEvent when activating an element via its accesskey. Removing the
  # accesskey attribute of all elements which would be triggered is the only way to stop the browser from
  # doing this.
  # We return a function to restore all of the accesskeys, to be called at the corresponding keyup function.
  suppressAccesskeyAction: do ->
    accesskeyToElems = null # Mapping of accesskey -> [elements]

    # Generate a cache of elements with accesskey set.
    generateAccesskeyToElems = ->
      accesskeyToElems = []
      accesskeyElementList = document.querySelectorAll("*[accesskey]")
      for element in accesskeyElementList
        accesskey = element.getAttribute("accesskey").toLowerCase()
        (accesskeyToElems[accesskey] ?= []).push element

    (event) ->
      return unless event.type == "keydown"

      # The key combo to activate an accesskey element is a printing character with the modifiers:
      #  * alt        on Windows/Linux
      #  * ctrl, alt  on Mac
      accesskey = KeyboardUtils.getKeyChar(event).toLowerCase()
      return unless event.ctrlKey == (KeyboardUtils.platform == "Mac") and
                    event.altKey == true and
                    accesskey.length == 1

      generateAccesskeyToElems() unless accesskeyToElems?
      return unless accesskey of accesskeyToElems # Nothing to do if no elements capture this key
      element.removeAttribute("accesskey") for element in accesskeyToElems[accesskey]
      return ->
        element.setAttribute("accesskey", accesskey) for element in accesskeyToElems[accesskey]
        @remove?()
        true


root = exports ? window
root.DomUtils = DomUtils
