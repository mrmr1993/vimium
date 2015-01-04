# NOTE(smblott).  Ultimately, all of the FindMode-related code should be moved to this file.

# When we use find mode, the selection/focus can end up in a focusable/editable element.  Subsequent keyboard
# events could drop us into insert mode, which is a bad user experience.  The PostFindMode mode is installed
# after find events to prevent this.
#
# PostFindMode also maps Esc (on the next keystroke) to immediately drop into insert mode.
class PostFindMode extends InsertModeBlocker
  constructor: (findModeAnchorNode) ->
    element = document.activeElement

    super PostFindMode, element,
      name: "post-find"

    return @exit() unless element and findModeAnchorNode

    # Special cases only arise if the active element is focusable.  So, exit immediately if it is not.
    canTakeInput = DomUtils.isSelectable(element) and DomUtils.isDOMDescendant findModeAnchorNode, element
    canTakeInput ||= element?.isContentEditable
    return @exit() unless canTakeInput

    # If the very-next key is Esc, then drop straight into insert mode.
    self = @
    @push
      keydown: (event) ->
        if element == document.activeElement and KeyboardUtils.isEscape event
          self.exit()
          new InsertMode element
          return false
        @remove()
        true

    # Install various ways in which we can leave this mode.
    @push
      DOMActive: (event) => handlerStack.alwaysContinueBubbling => @exit()
      click: (event) => handlerStack.alwaysContinueBubbling => @exit()
      focus: (event) => handlerStack.alwaysContinueBubbling => @exit()
      blur: (event) => handlerStack.alwaysContinueBubbling => @exit()
      keydown: (event) => handlerStack.alwaysContinueBubbling => @exit() if document.activeElement != element

root = exports ? window
root.PostFindMode = PostFindMode
