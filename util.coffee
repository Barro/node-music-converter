async = require "async"
child_process = require "child_process"
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


exports.findExecutable = (candidates, arguments_, callback) ->
  isExecutable = (candidate, work_callback) ->
    process = child_process.spawn candidate, arguments_
    process.on "error", =>
      work_callback null, [candidate, false]
    process.on 'exit', (code) =>
      work_callback null, [candidate, true]

  async.map candidates, isExecutable, (err, results) ->
    for [candidate, executable] in results
      if executable
        callback candidate
        return
    callback null
