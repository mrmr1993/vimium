class Renderer
  constructor: ->
    @viewport = {left: 0, top: 0, right: window.innerWidth, bottom: window.innerHeight}

  inViewport: (elementInfo) ->
    elementInfo.boundingRect = elementInfo.element.getBoundingClientRect()
    # Don't need to use intersectsStrict here, since we don't care about 0-width intersections.
    # NOTE(mrmr1993): This also excluded display: none; elements, which have {left: 0, right: 0, ...}
    Rect.intersects elementInfo.boundingRect, @viewport

  isClipping: (elementInfo) ->
    return elementInfo.clips if elementInfo.clips?
    # Most elements have no overflow CSS set, so it is usually cheaper to check this.
    computedStyle = window.getComputedStyle elementInfo.element
    elementInfo.overflow = computedStyle.overflow
    if elementInfo.overflow
      elementInfo.overflowX = elementInfo.overflowY = elementInfo.overflow
    else
      elementInfo.overflowX = computedStyle.overflowX
      elementInfo.overflowY = computedStyle.overflowY

    if elementInfo.overflow == "visible"
      elementInfo.clips = elementInfo.clipsX = elementInfo.clipsY = false
    else if elementInfo.overflowX == "visible"
      elementInfo.clipsX = false
      elementInfo.clips = elementInfo.clipsY = true
    else if elementInfo.overflowY == "visible"
      elementInfo.clipsY = false
      elementInfo.clips = elementInfo.clipsX = true
    else
      elementInfo.clips = elementInfo.clipsX = elementInfo.clipsY = true

  position: (elementInfo) -> elementInfo.position ?= window.getComputedStyle(elementInfo.element).position

  getClippingRect: (elementInfo) ->
    return elementInfo.clippingRect if elementInfo.clippingRect?
    if @isClipping elementInfo
      isAbsolute = "absolute" == @position elementInfo
      if elementInfo.parentInfo?
        if isAbsolute
          clippingRect = @getAbsClippingRect elementInfo.parentInfo
        else
          clippingRect = @getClippingRect elementInfo.parentInfo
      else
        clippingRect = @viewport

      if elementInfo.clippedRect?
        if elementInfo.clipsX
          if elementInfo.clipsY
            elementInfo.clippingRect = Rect.intersect elementInfo.clippedRect, clippingRect
          else
            elementInfo.clippingRect =
              left: Math.max elementInfo.clippedRect.left, clippingRect.left
              right: Max.min elementInfo.clippedRect.right, clippingRect.right
              top: clippingRect.top
              bottom: clippingRect.bottom
        else # elementInfo.clipsY
          elementInfo.clippingRect =
            left: clippingRect.left
            right: clippingRect.right,
            top: Math.max elementInfo.clippedRect.top, clippingRect.top
            bottom: Max.min elementInfo.clippedRect.bottom, clippingRect.bottom
        elementInfo.absClippingRect = elementInfo.clippingRect if isAbsolute
      else
        elementInfo.clippingRect = {left: 0, right: 0, top: 0, bottom: 0}
        elementInfo.absClippingRect = elementInfo.clippingRect if isAbsolute
    else
      if "absolute" == @position.elementInfo
        if elementInfo.parentInfo?
          elementInfo.clippingRect = elementInfo.absClippingRect = @getAbsClippingRect elementInfo.parentInfo
        else
          elementInfo.clippingRect = elementInfo.absClippingRect = @viewport
      else
        if elementInfo.parentInfo?
          elementInfo.clippingRect = @getClippingRect elementInfo.parentInfo
        else
         elementInfo.clippingRect = @viewport

    elementInfo.clippingRect

  getAbsClippingRect: (elementInfo) ->
    # This is called after getClippingRect, which computes elementInfo.absClippingRect for us if relevant.
    return elementInfo.absClippingRect if elementInfo.absClippingRect?
    if elementInfo.parentInfo?
      elementInfo.absClippingRect = @getAbsClippingRect elementInfo.parentInfo
    else
      elementInfo.absClippingRect = @viewport

  clipBy: (elementInfo, clippingElementInfo) ->
    clippingRect = @getClippingRect clippingElementInfo
    return if Rect.contains elementInfo.clippedRect, clippingRect
    if "absolute" != @position elementInfo
      elementInfo.clippedRect = Rect.intersect elementInfo.clippedRect, clippingRect
    else
      absClippingRect = @getAbsClippingRect clippingElementInfo
      elementInfo.clippedRect = Rect.intersect elementInfo.clippedRect, absClippingRect
    return

  rendered: (elementInfo) ->
    elementInfo.rendered ?=
      elementInfo.clippedRect.left < elementInfo.clippedRect.right and
      elementInfo.clippedRect.top < elementInfo.clippedRect.bottom

  setOverflowingElement: (elementInfo, ancestorInfo, checkBounds) ->
    if not checkBounds or Rect.contains elementInfo.clippedRect, ancestorInfo.clippedRect
      (ancestorInfo.overflowingElements ?= []).push elementsInfo
      @setOverflowingElement elementInfo, ancestorInfo.parentInfo, true if ancestorInfo.parentInfo?

  # - processRendered is called on each rendered element as it is found
  # - processRenderedDescendents is called on each unrendered element with rendered children *after*
  #   every child has been processed, but before any outer ancestors are processed
  # Both of these are passed the elementInfo struct used internally by renderer as their only argument.
  getRenderedElements: (root, processRendered = (->), processRenderedDecendents = (->)) ->
    element = root
    parentStack = []
    renderedElements = []
    elementIndex = 0
    while element
      parentInfo = parentStack[parentStack.length - 1]
      elementInfo = {element, parentInfo, elementIndex: elementIndex++}
      if @inViewport elementInfo
        elementInfo.clippedRect = Rect.intersect elementInfo.boundingRect, @viewport

        if parentInfo?
          if parentInfo.clippedRect? and Rect.contains elementInfo.clippedRect, parentInfo.clippedRect
            processRendered elementInfo
            renderedElements.push elementInfo
          else
            @clipBy elementInfo, parentInfo
            if @rendered elementInfo
              processRendered elementInfo
              renderedElements.push elementInfo
              @setOverflowingElement elementInfo, parentInfo
      else
        elementInfo.rendered = false

      currentElement = elementInfo
      element = currentElement.element.firstElementChild
      if element
        parentStack.push currentElement
      else
        element = currentElement.element.nextElementSibling

        while currentElement and not element
          currentElement = parentStack.pop()
          break unless currentElement
          if not currentElement.rendered and currentElement.overflowingElements
            processRenderedDecendents elementInfo
          element = currentElement.element.nextElementSibling

    renderedElements

  getImageMapRects: (elementInfo) ->
    element = elementInfo.element
    if element.tagName.toLowerCase?() == "img"
      mapName = element.getAttribute "usemap"
      if mapName
        mapName = mapName.replace(/^#/, "").replace("\"", "\\\"")
        map = document.querySelector "map[name=\"#{mapName}\"]"
        if map and imgClientRects.length > 0
          areas = map.getElementsByTagName "area"
          DomUtils.getClientRectsForAreas elementInfo.clippedRect, areas, elementInfo.clippedRect

  #
  # Determine whether the element is visible and clickable. If it is, find the rect bounding the element in
  # the viewport.  There may be more than one part of element which is clickable (for example, if it's an
  # image), therefore we always return a array of element/rect pairs (which may also be a singleton or empty).
  #
  isVisibleClickable: (elementInfo) ->
    # Get the tag name.  However, `element.tagName` can be an element (not a string, see #2305), so we guard
    # against that.
    element = elementInfo.element
    tagName = element.tagName.toLowerCase?() ? ""
    isClickable = false
    onlyHasTabIndex = false
    possibleFalsePositive = false
    visibleElements = []
    reason = null

    # Check aria properties to see if the element should be ignored.
    if (element.getAttribute("aria-hidden")?.toLowerCase() in ["", "true"] or
        element.getAttribute("aria-disabled")?.toLowerCase() in ["", "true"])
      return false # This element should never have a link hint.

    # Check for AngularJS listeners on the element.
    @checkForAngularJs ?= do ->
      angularElements = document.getElementsByClassName "ng-scope"
      if angularElements.length == 0
        -> false
      else
        ngAttributes = []
        for prefix in [ '', 'data-', 'x-' ]
          for separator in [ '-', ':', '_' ]
            ngAttributes.push "#{prefix}ng#{separator}click"
        (element) ->
          for attribute in ngAttributes
            return true if element.hasAttribute attribute
          false

    isClickable ||= @checkForAngularJs element

    # Check for attributes that make an element clickable regardless of its tagName.
    if element.hasAttribute("onclick") or
        (role = element.getAttribute "role") and role.toLowerCase() in [
          "button" , "tab" , "link", "checkbox", "menuitem", "menuitemcheckbox", "menuitemradio"
        ] or
        (contentEditable = element.getAttribute "contentEditable") and
          contentEditable.toLowerCase() in ["", "contenteditable", "true"]
      isClickable = true

    # Check for jsaction event listeners on the element.
    if not isClickable and element.hasAttribute "jsaction"
      jsactionRules = element.getAttribute("jsaction").split(";")
      for jsactionRule in jsactionRules
        ruleSplit = jsactionRule.trim().split ":"
        if 1 <= ruleSplit.length <= 2
          [eventType, namespace, actionName ] =
            if ruleSplit.length == 1
              ["click", ruleSplit[0].trim().split(".")..., "_"]
            else
              [ruleSplit[0], ruleSplit[1].trim().split(".")..., "_"]
          isClickable ||= eventType == "click" and namespace != "none" and actionName != "_"

    # Check for tagNames which are natively clickable.
    switch tagName
      when "a"
        isClickable = true
      when "textarea"
        isClickable ||= not element.disabled and not element.readOnly
      when "input"
        isClickable ||= not (element.getAttribute("type")?.toLowerCase() == "hidden" or
                             element.disabled or
                             (element.readOnly and DomUtils.isSelectable element))
      when "button", "select"
        isClickable ||= not element.disabled
      when "label"
        isClickable ||= element.control? and not element.control.disabled and
                        not @getVisibleClickable element.control
      when "body"
        isClickable ||=
          if element == document.body and not windowIsFocused() and
              window.innerWidth > 3 and window.innerHeight > 3 and
              document.body?.tagName.toLowerCase() != "frameset"
            reason = "Frame."
        isClickable ||=
          if element == document.body and windowIsFocused() and Scroller.isScrollableElement element
            reason = "Scroll."
      when "img"
        isClickable ||= element.style.cursor in ["zoom-in", "zoom-out"]
      when "div", "ol", "ul"
        isClickable ||=
          if element.clientHeight < element.scrollHeight and Scroller.isScrollableElement element
            reason = "Scroll."
      when "details"
        isClickable = true
        reason = "Open."

    # An element with a class name containing the text "button" might be clickable.  However, real clickables
    # are often wrapped in elements with such class names.  So, when we find clickables based only on their
    # class name, we mark them as unreliable.
    if not isClickable and 0 <= element.getAttribute("class")?.toLowerCase().indexOf "button"
      possibleFalsePositive = isClickable = true

    # Elements with tabindex are sometimes useful, but usually not. We can treat them as second class
    # citizens when it improves UX, so take special note of them.
    tabIndexValue = element.getAttribute("tabindex")
    tabIndex = if tabIndexValue == "" then 0 else parseInt tabIndexValue
    unless isClickable or isNaN(tabIndex) or tabIndex < 0
      isClickable = onlyHasTabIndex = true

    if isClickable
      {element, secondClassCitizen: onlyHasTabIndex, possibleFalsePositive, reason}
    else
      false

  getLinkHint

root = exports ? (window.root ?= {})
root.Renderer = Renderer
extend window, root unless exports?
