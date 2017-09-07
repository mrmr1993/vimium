require "chromedriver"
{Builder} = require "selenium-webdriver"
chrome = require "selenium-webdriver/chrome"

options = new chrome.Options()
options.addArguments "load-extension=."

exports.driver = new Builder()
    .forBrowser("chrome")
    .setChromeOptions(options)
    .build()
