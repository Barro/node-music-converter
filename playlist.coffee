crypto = require "crypto"
fs = require "fs"
lazy = require 'lazy'
_s = require "underscore.string"

exports.AudaciousPlaylistParser = class AudaciousPlaylistParser
        parse: (file, callback) =>
                filereader = new lazy fs.createReadStream(file)
                result = []
                currentItem = null
                # The first line is playlist's title.
                filereader.lines.skip(1).forEach (filenameBuffer) =>
                        line = filenameBuffer.toString "utf-8"
                        [option, value] = line.split "=", 2
                        value = decodeURIComponent value
                        if option == "uri"
                                if currentItem != null
                                        result.push currentItem
                                currentItem =
                                        uri: value
                                if _s.startsWith value, "file://"
                                        currentItem.filename = value.substring "file://".length
                        else if value
                                currentItem[option] = value

                filereader.on "error", (err) =>
                        callback "Failed to parse Audacious data file: #{err}."

                filereader.on "end", =>
                        result.push currentItem
                        callback null, result


exports.FilenamePerLineParser = class FilenamePerLineParser
        parse: (filename, callback) =>
                result = []
                filereader = new lazy fs.createReadStream(filename)
                filereader.lines.forEach (filenameBuffer) =>
                        filename = filenameBuffer.toString "utf-8"
                        result.push {filename: filename}

                filereader.on "error", (err) =>
                        callback "Failed to parse text data file: #{err}."

                filereader.on "end", =>
                        callback null, result


exports.Parser = class Parser
        constructor: (@log) ->
                @filenamePerLine = new FilenamePerLineParser()
                @audaciousPlaylist = new AudaciousPlaylistParser()

        _createChecksum: (err, filename, files, callback) =>
                if err
                        callback err, null
                        return
                hash = crypto.createHash "sha512"
                stream = fs.ReadStream filename
                stream.on "data", (data) =>
                        hash.update data
                stream.on "end", =>
                        checksum = hash.digest "hex"
                        result =
                                files: files
                                cacheKey: checksum
                        callback err, result

        parse: (filename, callback) =>
                @log.info "Reading song database file: '#{filename}'."
                if _s.endsWith filename, ".txt"
                        @filenamePerLine.parse filename, (err, result) =>
                                @_createChecksum err, filename, result, callback
                else if _s.endsWith filename, ".audpl"
                        @audaciousPlaylist.parse filename, (err, result) =>
                                @_createChecksum err, filename, result, callback
                else
                        callback "Failed to recognize format for file '#{filename}'"
