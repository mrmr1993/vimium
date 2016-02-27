
class KeyHandlerMode extends Mode
  useCount: true
  countPrefix: 0
  keydownEvents: {}
  keyState: []

  constructor: (options) ->
    # A function accepting a command name and a count; required.
    @commandHandler = options.commandHandler ? (->)
    @useCount = false if options.noCount
    @reset()

    # We don't pass these options on to super().
    options = Utils.copyObjectOmittingProperties options, "commandHandler", "keyMapping", "noCount"

    super extend options,
      keydown: @onKeydown.bind this
      keypress: @onKeypress.bind this
      keyup: @onKeyup.bind this
      # We cannot track matching keydown/keyup events if we lose the focus.
      blur: (event) => @alwaysContinueBubbling =>
        @keydownEvents = {} if event.target == window

  setKeyMapping: (@keyMapping) -> @reset()

  onKeydown: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event

    if KeyboardUtils.isEscape event
      if @isInResetState()
        @continueBubbling
      else
        @reset()
        DomUtils.suppressKeyupAfterEscape handlerStack
        false # Suppress event.

    else if keyChar and @mappingForKeyChar keyChar
      @handleKeyChar event, keyChar

    else
      # We did not handle the event, but we might handle the subsequent keypress event.  If we *will* be
      # handling that event, then we need to suppress propagation of this keydown event to prevent triggering
      # page features like Google instant search.
      keyChar = KeyboardUtils.getKeyChar event
      if keyChar and (@mappingForKeyChar(keyChar) or @isCountKey keyChar)
        DomUtils.suppressPropagation event
        @keydownEvents[@getEventCode event] = true
        @stopBubblingAndTrue
      else
        @countPrefix = 0 if keyChar
        @continueBubbling

  onKeypress: (event) ->
    keyChar = KeyboardUtils.getKeyCharString event
    if keyChar and @mappingForKeyChar keyChar
      @handleKeyChar event, keyChar
    else if keyChar and @isCountKey keyChar
      @reset @countPrefix * 10 + parseInt keyChar
      false # Suppress event.
    else
      @continueBubbling

  onKeyup: (event) ->
    eventCode = @getEventCode event
    if eventCode of @keydownEvents
      delete @keydownEvents[eventCode]
      DomUtils.suppressPropagation event
      @stopBubblingAndTrue
    else
      @continueBubbling

  handleKeyChar: (event, keyChar) ->
    @advanceKeyState keyChar
    commands = @keyState.filter (entry) -> entry.command
    @invokeCommand commands[0] if 0 < commands.length
    false # Suppress event.

  # This returns the first mapping for which keyChar is mapped. The return value is truthy if a match is found
  # and falsy otherwise.
  mappingForKeyChar: (keyChar) ->
    for mapping in @keyState
      return mapping if keyChar of mapping
    null

  # This is called whenever a keyChar is matched.  We keep any existing entries matching keyChar, and append a
  # new copy of the global key mappings.
  advanceKeyState: (keyChar) ->
    newKeyState =
      for mapping in @keyState
        continue unless keyChar of mapping
        mapping[keyChar]
    @keyState = [newKeyState..., @keyMapping]

  # This is called to invoke a command and reset the key state.
  invokeCommand: (command) ->
    countPrefix = if 0 < @countPrefix then @countPrefix else 1
    @reset()
    @commandHandler command, countPrefix

  # Reset the state (as if no keys had been handled), but retaining the count - if one is provided.
  reset: (count = 0) ->
    @countPrefix = count
    @keyState = [@keyMapping]

  # This tests whether we are in the reset state.  It is used to check whether we should be using escape to
  # reset the key state, or passing it to the page.
  isInResetState: ->
    @countPrefix == 0 and @keyState.length == 1

  # This tests whether keyChar should be treated as a count key.
  isCountKey: (keyChar) ->
    return false unless @useCount and keyChar.length == 1
    if 0 < @countPrefix
      '0' <= keyChar <= '9'
    else
      '1' <= keyChar <= '9'

  # True if keyChar would be the first character of a command mapping.  This is used by passKeys to decide
  # whether keyChar is a continuation of a command which the user has already begin entering.
  isFirstKeyChar: (keyChar) ->
    @countPrefix == 0 and @keyMapping == @mappingForKeyChar keyChar

  getEventCode: (event) -> event.keyCode

root = exports ? window
root.KeyHandlerMode = KeyHandlerMode
