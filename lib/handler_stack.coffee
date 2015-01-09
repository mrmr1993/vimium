root = exports ? window

class HandlerStack

  constructor: ->
    @debug = 1
    @stack = []
    @counter = 0

    # A handler should return this value to immediately discontinue bubbling and pass the event on to the
    # underlying page.
    @stopBubblingAndTrue = new Object()

    # A handler should return this value to indicate that the event has been consumed, and no further
    # processing should take place.
    @stopBubblingAndFalse = new Object()

  # Adds a handler to the top of the stack. Returns a unique ID for that handler that can be used to remove it
  # later.
  push: (handler) ->
    @stack.push handler
    handler.id = ++@counter

  # Adds a handler to the bottom of the stack. Returns a unique ID for that handler that can be used to remove
  # it later.
  unshift: (handler) ->
    @stack.unshift handler
    handler.id = ++@counter

  # Called whenever we receive a key or other event. Each individual handler has the option to stop the
  # event's propagation by returning a falsy value, or stop bubbling by returning @stopBubblingAndFalse or
  # @stopBubblingAndTrue.
  bubbleEvent: (type, event) ->
    count = @debug++
    # extra is passed to each handler.  This allows handlers to pass information down the stack.
    extra = {}
    # We take a copy of the array, here, in order to avoid interference from concurrent removes (for example,
    # to avoid calling the same handler twice).
    for handler in @stack[..].reverse()
      # A handler may have been removed (handler.id == null).
      if handler and handler.id
        @currentId = handler.id
        # A handler can register a handler for type "all", which will be invoked on all events.  Such an "all"
        # handler will be invoked first.
        for func in [ handler.all, handler[type] ]
          if func
            passThrough = func.call @, event, extra
            @log count, type, extra, handler, event, passThrough if @debug
            if not passThrough
              DomUtils.suppressEvent(event) if @isChromeEvent event
              return false
            return true if passThrough == @stopBubblingAndTrue
            return false if passThrough == @stopBubblingAndFalse
    true

  remove: (id = @currentId) ->
    for i in [(@stack.length - 1)..0] by -1
      handler = @stack[i]
      if handler.id == id
        handler.id = null
        @stack.splice(i, 1)
        break

  # The handler stack handles chrome events (which may need to be suppressed) and internal (pseudo) events.
  # This checks whether the event at hand is a chrome event.
  isChromeEvent: (event) ->
    event?.preventDefault? or event?.stopImmediatePropagation?

  # Convenience wrappers.
  alwaysContinueBubbling: (handler) ->
    handler()
    true

  neverContinueBubbling: (handler) ->
    handler()
    false

  log: (count, type, extra, handler, event, passThrough) ->
    result = "suppress"
    result = "continue" if passThrough
    result = "stop-true" if passThrough == @stopBubblingAndTrue
    result = "stop-false" if passThrough == @stopBubblingAndFalse
    console.log count, type, (handler?.name || "anon"), result

root.HandlerStack = HandlerStack
root.handlerStack = new HandlerStack
