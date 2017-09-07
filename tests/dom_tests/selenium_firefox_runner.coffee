require "geckodriver"
{Builder} = require "selenium-webdriver"
firefox = require "selenium-webdriver/firefox"

profile = new firefox.Profile()
profile.addExtension "."
profile.setPreference "extensions.firebug.showChromeErrors", true

options = new firefox.Options().setProfile profile
exports.driver = new Builder()
    .forBrowser("firefox")
    .setFirefoxOptions(options)
    .build()
