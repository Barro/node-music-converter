fs = require "fs"


escapeRegExp = (str) ->
  return str.replace /[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, "\\$&"


exports.PrefixStripper = class PrefixStripper
  constructor: (@prefixes) ->
    prefixRegexArray = (escapeRegExp prefix for prefix in prefixes)
    prefixRegex = prefixRegexArray.join "|"
    @replacer = new RegExp "^(#{prefixRegex})"

  strip: (filename) =>
    return filename.replace @replacer, ""


exports.createPrefixStripper = (filename) ->
  prefixes = fs.readFileSync filename, "utf-8"
  prefixLines = prefixes.split "\n"
  prefixes = []
  for line in prefixLines
    if not line
      continue
    prefixes.push line
  stripper = new PrefixStripper prefixes
  return stripper
