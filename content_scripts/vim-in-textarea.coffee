
# Activation key is Control-Alt-V.
isVimActivationEvent = (event) ->
  console.log event
  event.ctrlKey and
    event.altKey and
    not event.metaKey and
    event.keyCode == 86 # "V"

document.addEventListener "DOMContentLoaded", ->
  for ele in document.getElementsByTagName "textarea"
    do (ele) ->
      # TODO(smblott) Is there a better way to record that vim is activated?
      # TODO(smblott) Can we disable the listener once vim is activated?
      # TODO(smblott) How can we visually show that vim is activated?
      ele.addEventListener "keydown", (event) ->
        if not ele.__vimium_vim_attached and isVimActivationEvent event
          vim = ele.__vimium_vim_attached = new VIM()
          vim.attach_to ele
          event.preventDefault()
          event.stopPropagation()

