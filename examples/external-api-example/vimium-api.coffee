root = exports ? window

# This code is generic; it defines the interaction between Vimium and this extension, and could easily be
# re-used.
chrome.runtime.onMessageExternal.addListener (request, sender, sendResponse) ->
  # If required, verify the sender here.
  {name, command} = request
  switch name
    when "prepare"
      if Commands.syncCommands[command]? or Commands.asyncCommands[command]?
        sendResponse name: "ready", blockKeyboardActivity: Commands.syncCommands[command]?

    when "execute"
      {count} = request
      if Commands.syncCommands[command]?
        Commands.syncCommands[command] count, sendResponse
        true # We will be calling sendResponse().

      else if Commands.asyncCommands[command]?
        Commands.asyncCommands[command] count
        false # We will not be calling sendResponse().

      else
        false

    else
      false

registerWithVimium = ->
  chrome.storage.sync.get "vimiumId", ({vimiumId}) ->
    chrome.runtime.sendMessage vimiumId,
      name: "registerExternalExtension", extensionName: Commands.extensionName, extensionId: chrome.runtime.id

root.setVimiumId = (vimiumId, force = false) ->
  chrome.storage.sync.get "vimiumId", (items) ->
    if force or not items.vimiumId
      chrome.storage.sync.set {vimiumId}, registerWithVimium
    else
      registerWithVimium()

# This is the Chrome Store Vimium extension Id.
setVimiumId "dbepggeogbaibhgnhhndojpepiihcmeb"

# If you run Vimium with a custom extension Id, then run the following (or similar) in the background page of
# this extension:
# setVimiumId("hiihfcebjbnoniicphblpiekhfmbdmog", true)

