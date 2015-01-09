
class EditMode extends InsertModeBlocker
  keys: "i".split //

  handleKeyChar: (keyChar) ->
    switch keyChar
      when "i"
        new InsertMode
          targetElement: @options.targetElement
          blurOnExit: false

  constructor: (options) ->
    super
      name: "edit"
      badge: "E"
      exitOnEscape: true
      exitOnBlur: options.targetElement
      targetElement: options.targetElement

      keydown: (event) =>
        keyChar = KeyboardUtils.getKeyChar event
        if keyChar in @keys
          DomUtils.suppressPropagation event
          @stopBubblingAndTrue
        else
          @suppressEvent

      keypress: (event) =>
        @handleKeyChar String.fromCharCode event.charCode
        @suppressEvent

      keyup: (event) =>
        @suppressEvent

  exit: ->
    super()
    document.activeElement.blur() if document.activeElement
    # For contentEdible elements, we need to be a bit more forceful.  Taken from:
    # http://stackoverflow.com/questions/12353247/force-contenteditable-div-to-stop-accepting-input-after-it-loses-focus-under-web
    window.getSelection()?.removeAllRanges()

root = exports ? window
root.EditMode = EditMode
