Utils =
  getCurrentVersion: ->
    chrome.runtime.getManifest().version

  # Takes a dot-notation object string and call the function
  # that it points to with the correct value for 'this'.
  invokeCommandString: (str, argArray) ->
    components = str.split('.')
    obj = window
    for component in components[0...-1]
      obj = obj[component]
    func = obj[components.pop()]
    func.apply(obj, argArray)

  # Creates a single DOM element from :html
  createElementFromHtml: (html) ->
    tmp = document.createElement("div")
    tmp.innerHTML = html
    tmp.firstChild

  escapeHtml: (string) -> string.replace(/</g, "&lt;").replace(/>/g, "&gt;")

  # Generates a unique ID
  createUniqueId: do ->
    id = 0
    -> id += 1

  hasChromePrefix: do ->
    chromePrefixes = [ "about:", "view-source:", "extension:", "chrome-extension:", "data:" ]
    (url) ->
      for prefix in chromePrefixes
        return true if url.startsWith prefix
      false

  hasJavascriptPrefix: (url) ->
    url.startsWith "javascript:"

  hasFullUrlPrefix: do ->
    urlPrefix = new RegExp "^[a-z]{3,}://."
    (url) -> urlPrefix.test url

  # Completes a partial URL (without scheme)
  createFullUrl: (partialUrl) ->
    if @hasFullUrlPrefix(partialUrl) then partialUrl else ("http://" + partialUrl)

  # Tries to detect if :str is a valid URL.
  isUrl: (str) ->
    # Must not contain spaces
    return false if ' ' in str

    # Starts with a scheme: URL
    return true if @hasFullUrlPrefix str

    # More or less RFC compliant URL host part parsing. This should be sufficient for our needs
    urlRegex = new RegExp(
      '^(?:([^:]+)(?::([^:]+))?@)?' + # user:password (optional) => \1, \2
      '([^:]+|\\[[^\\]]+\\])'       + # host name (IPv6 addresses in square brackets allowed) => \3
      '(?::(\\d+))?$'                 # port number (optional) => \4
      )

    # Official ASCII TLDs that are longer than 3 characters + inofficial .onion TLD used by TOR
    longTlds = ['arpa', 'asia', 'coop', 'info', 'jobs', 'local', 'mobi', 'museum', 'name', 'onion']

    specialHostNames = ['localhost']

    # Try to parse the URL into its meaningful parts. If matching fails we're pretty sure that we don't have
    # some kind of URL here.
    match = urlRegex.exec (str.split '/')[0]
    return false unless match
    hostName = match[3]

    # Allow known special host names
    return true if hostName in specialHostNames

    # Allow IPv6 addresses (need to be wrapped in brackets as required by RFC). It is sufficient to check for
    # a colon, as the regex wouldn't match colons in the host name unless it's an v6 address
    return true if ':' in hostName

    # At this point we have to make a decision. As a heuristic, we check if the input has dots in it. If yes,
    # and if the last part could be a TLD, treat it as an URL
    dottedParts = hostName.split '.'

    if dottedParts.length > 1
      lastPart = dottedParts.pop()
      return true if 2 <= lastPart.length <= 3 or lastPart in longTlds

    # Allow IPv4 addresses
    return true if /^(\d{1,3}\.){3}\d{1,3}$/.test hostName

    # Fallback: no URL
    return false

  # Map a search query to its URL encoded form. The query may be either a string or an array of strings.
  # E.g. "BBC Sport" -> "BBC+Sport".
  createSearchQuery: (query) ->
    query = query.split(/\s+/) if typeof(query) == "string"
    query.map(encodeURIComponent).join "+"

  # Create a search URL from the given :query (using either the provided search URL, or the default one).
  # It would be better to pull the default search engine from chrome itself.  However, chrome does not provide
  # an API for doing so.
  createSearchUrl: (query, searchUrl = Settings.get("searchUrl")) ->
    searchUrl += "%s" unless 0 <= searchUrl.indexOf "%s"
    searchUrl.replace /%s/g, @createSearchQuery query

  # Converts :string into a Google search if it's not already a URL. We don't bother with escaping characters
  # as Chrome will do that for us.
  convertToUrl: (string) ->
    string = string.trim()

    # Special-case about:[url], view-source:[url] and the like
    if Utils.hasChromePrefix string
      string
    else if Utils.hasJavascriptPrefix string
      # We blindly URL decode javascript: URLs.  That's what Chrome does when they're clicked, or entered into
      # the omnibox.  However, Chrome does not URL decode such URLs in chrome.tabs.update.
      # This is arguably a Chrome bug.  See https://code.google.com/p/chromium/issues/detail?id=483000.
      decodeURI string
    else if Utils.isUrl string
      Utils.createFullUrl string
    else
      Utils.createSearchUrl string

  # detects both literals and dynamically created strings
  isString: (obj) -> typeof obj == 'string' or obj instanceof String

  # Transform "zjkjkabz" into "abjkz".
  distinctCharacters: (str) ->
    unique = ""
    for char in str.split("").sort()
      unique += char unless 0 <= unique.indexOf char
    unique

  # Compares two version strings (e.g. "1.1" and "1.5") and returns
  # -1 if versionA is < versionB, 0 if they're equal, and 1 if versionA is > versionB.
  compareVersions: (versionA, versionB) ->
    versionA = versionA.split(".")
    versionB = versionB.split(".")
    for i in [0...(Math.max(versionA.length, versionB.length))]
      a = parseInt(versionA[i] || 0, 10)
      b = parseInt(versionB[i] || 0, 10)
      if (a < b)
        return -1
      else if (a > b)
        return 1
    0

  # True if the current Chrome version is at least the required version.
  haveChromeVersion: (required) ->
    chromeVersion = navigator.appVersion.match(/Chrome\/(.*?) /)?[1]
    chromeVersion and 0 <= Utils.compareVersions chromeVersion, required

  # Zip two (or more) arrays:
  #   - Utils.zip([ [a,b], [1,2] ]) returns [ [a,1], [b,2] ]
  #   - Length of result is `arrays[0].length`.
  #   - Adapted from: http://stackoverflow.com/questions/4856717/javascript-equivalent-of-pythons-zip-function
  zip: (arrays) ->
    arrays[0].map (_,i) ->
      arrays.map( (array) -> array[i] )

  # locale-sensitive uppercase detection
  hasUpperCase: (s) -> s.toLowerCase() != s

  # Give objects (including elements) distinct identities.
  getIdentity: do ->
    identities = []

    (obj) ->
      index = identities.indexOf obj
      if index < 0
        index = identities.length
        identities.push obj
      "identity-" + index

  # Return a copy of object, but with some of its properties omitted.
  copyObjectOmittingProperties: (obj, properties...) ->
    obj = extend {}, obj
    delete obj[property] for property in properties
    obj

  # Does string match any of these regexps?
  matchesAnyRegexp: (regexps, string) ->
    for re in regexps
      return true if re.test string
    false

  # Convenience wrapper for setTimeout (with the arguments around the other way).
  setTimeout: (ms, func) -> setTimeout func, ms

  # Like Nodejs's nextTick.
  nextTick: (func) -> @setTimeout 0, func


# This creates a new function out of an existing function, where the new function takes fewer arguments. This
# allows us to pass around functions instead of functions + a partial list of arguments.
Function::curry = ->
  fixedArguments = Array.copy(arguments)
  fn = this
  -> fn.apply(this, fixedArguments.concat(Array.copy(arguments)))

Array.copy = (array) -> Array.prototype.slice.call(array, 0)

String::startsWith = (str) -> @indexOf(str) == 0

globalRoot = window ? global
globalRoot.extend = (hash1, hash2) ->
  for key of hash2
    hash1[key] = hash2[key]
  hash1

# A simple cache. Entries used within two expiry periods are retained, otherwise they are discarded.
# At most 2 * @entries entries are retained.
class SimpleCache
  # expiry: expiry time in milliseconds (default, one hour)
  # entries: maximum number of entries in @cache (there may be this many entries in @previous, too)
  constructor: (@expiry = 60 * 60 * 1000, @entries = 1000) ->
    @cache = {}
    @rotate() # Force start the rotation timer.

  rotate: ->
    @previous = @cache
    @cache = {}
    # We reset the timer every time the cache is rotated (which could be because a previous timer expired, or
    # because the number of @entries was exceeded.
    clearTimeout @timer if @timer?
    @timer = Utils.setTimeout @expiry, => @rotate()

  has: (key) ->
    (key of @cache) or key of @previous

  get: (key) ->
    if key of @cache
      @cache[key]
    else if key of @previous
      @cache[key] = @previous[key]
    else
      null

  # Set value, and return that value.  If value is null, then delete key.
  set: (key, value = null) ->
    if value?
      @cache[key] = value
      delete @previous[key]
      @rotate() if @entries < Object.keys(@cache).length
    else
      delete @cache[key]
      delete @previous[key]
    value

root = exports ? window
root.Utils = Utils
root.SimpleCache = SimpleCache
