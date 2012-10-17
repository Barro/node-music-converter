child_process = require 'child_process'
crypto = require 'crypto'
fs = require 'fs'
path = require 'path'
temp = require 'temp'

# 1 minute of 160 kbps music.
FAILED_CONVERSION_IS_OK_SIZE = 60 * 160 * 1000 / 8

class VorbisConverter
        suffix: =>
                return "ogg"

        audioType: =>
                return "audio/ogg"

        mimeType: =>
                return "application/ogg"

        convert: (source, bitrate, target, callback) =>
                options =
                        cwd: "/tmp/"
                ffmpeg = child_process.spawn "ffmpeg", ["-i", source, '-vn', '-acodec', 'libvorbis', '-ab', bitrate, '-y', '-loglevel', 'quiet', target], options
                ffmpeg.on 'exit', (code) =>
                        if code != 0
                                # We have failed file conversion. Let's check
                                # if the resulting file is large enough so that
                                # we can accept the conversion anyway.
                                fs.stat target, (err, stats) ->
                                        if err
                                                callback "Failed file conversion. No file exists."
                                                return
                                        if stats.size >= FAILED_CONVERSION_IS_OK_SIZE
                                                callback null
                                                return
                                        callback "Failed file conversion. Not enough data converted (#{stats.size} bytes)."
                                return
                        callback null


class Mp3Converter
        suffix:  =>
                return "mp3"

        audioType: =>
                return "audio/mpeg"

        mimeType: =>
                return "audio/mpeg"

        convert: (source, bitrate, target, callback) =>
                options =
                        cwd: "/tmp/"
                ffmpeg = child_process.spawn "ffmpeg", ["-i", source, '-vn', '-acodec', 'libmp3lame', '-ab', bitrate, '-y', '-loglevel', 'quiet', target], options
                ffmpeg.on 'exit', (code) =>
                        if code != 0
                                # We have failed file conversion. Let's check
                                # if the resulting file is large enough so that
                                # we can accept the conversion anyway.
                                fs.stat target, (err, stats) ->
                                        if err
                                                callback "Failed file conversion. No file exists."
                                                return
                                        if stats.size >= FAILED_CONVERSION_IS_OK_SIZE
                                                callback null
                                                return
                                        callback "Failed file conversion. Not enough data converted (#{stats.size} bytes)."
                                return
                        callback null

class FileCacheInstance
        constructor: (@cache, @conversionParams) ->

        createCache: (convertedFilename, callback) =>
                return @cache.createCache convertedFilename, @conversionParams, callback

        getCached: (callback) =>
                return @cache.getCached @conversionParams, callback

        getKey: =>
                return @cache.getDigest @conversionParams


exports.FileCache = class FileCache
        constructor: (@cachedir="/tmp", @cacheLocation) ->

        generate: (conversionParams) =>
                return new FileCacheInstance @, conversionParams

        getDigest: (conversionParams) ->
                paramList = []
                for key, value of conversionParams
                        paramList.push("#{key}:#{value}")
                paramList.sort()
                parameters = paramList.join("|")
                hashable = "#{parameters}"
                hash = crypto.createHash("sha512")
                hash.update(hashable)
                return hash.digest("hex")

        _createFilename: (conversionParams) =>
                digest = @getDigest conversionParams
                filename = "#{digest}.#{conversionParams.suffix}"
                return filename

        _getCacheName: (conversionParams) =>
                filename = @_createFilename conversionParams
                return path.join @cachedir, filename

        _getLocation: (conversionParams) =>
                filename = @_createFilename conversionParams
                return "#{@cacheLocation}/#{filename}"

        getCached: (conversionParams, callback) =>
                filepath = @_getCacheName conversionParams
                fs.exists filepath, (exists) =>
                        if not exists
                                callback "File '#{filepath}' does not exist.", null
                                return
                        callback null, @_getLocation conversionParams

        createCache: (convertedFilename, conversionParams, callback) =>
                filepath = @_getCacheName conversionParams
                input = fs.createReadStream convertedFilename
                input.on "error", (err) =>
                        console.log "Read stream error: #{err}"
                output = fs.createWriteStream filepath
                input.pipe output
                input.on "end", =>
                        callback null, @_getLocation conversionParams


class FileConverter
        constructor: (@log, @cache)->
                @bitrate = "160k"
                @converters =
                        mp3: new Mp3Converter()
                        ogg: new VorbisConverter()
                @_ongoingConversions = {}

        _redirectToCachefile: (cacheInstance, response) =>

        _createResponse: (err, cacheInstance, tempname, callback) =>
                if err
                        @log.error "Encoding error: #{err}."
                        fs.exists tempname, (exists) =>
                                if exists
                                        @log.debug "Unlinking file on error: #{tempname}."
                                        fs.unlink tempname, (err) =>
                                                if err
                                                        @log.warn "Failed to unlink file #{tempname}: #{err}"
                                callback {data: ["Failed to convert.", 500], headers: {}}
                                return
                        return
                fs.stat tempname, (statErr, stats) =>
                        if statErr
                                callback {data: ["Failed to read resulting file name.", 500], headers: {}}
                                return
                        @log.debug "Creating read stream for: #{tempname}."
                        stream = fs.createReadStream tempname
                        stream.on "end", =>
                                @log.debug "Finished reading #{tempname}."
                                fs.unlink tempname, (err) =>
                                        if err
                                                @log.warn "Failed to unlink file #{tempname} on stream end: #{err}"

                        cacheInstance.createCache tempname, (err, location) ->
                                callback {data: ["Go to #{location}", 302], headers: {"location": location}}

        _conversionDone: (err, cacheInstance, tempname) =>
                @log.debug "Conversion finished. Error: #{err}"
                @_createResponse err, cacheInstance, tempname, (responseParams) =>
                        @log.debug "Sending response to clients: #{tempname}."
                        for response in @_ongoingConversions[cacheInstance.getKey()]
                                for header, value of responseParams.headers
                                        response.set(header, value)
                                [content, code] = responseParams.data
                                response.send content, code
                        delete @_ongoingConversions[cacheInstance.getKey()]

        convert: (type, filename, response) =>
                @log.info "Starting conversion of '#{filename}' to type #{type}."
                if type not of @converters
                        response.send "I do not know how to convert to type #{type}.", 406
                        return
                converter = @converters[type]
                suffix = converter.suffix()

                conversionParams =
                        filename: filename
                        type: type
                        suffix: suffix
                        bitrate: @bitrate

                cacheInstance = @cache.generate conversionParams

                cacheInstance.getCached (err, location) =>
                        if not err
                                response.set "location", location
                                response.send "Go to #{location}", 302
                                return

                        fs.stat filename, (statErr, stats) =>
                                if statErr
                                        response.send "Failed to read original file name.", 500
                                        return

                                cacheKey = cacheInstance.getKey()
                                if cacheKey of @_ongoingConversions
                                        @log.debug "Adding #{cacheKey} to ongoing encodings."
                                        @_ongoingConversions[cacheKey].push response
                                        return
                                else
                                        @log.debug "Creating new ongoing encoding cache key #{cacheKey}."
                                        @_ongoingConversions[cacheKey] = [response]

                                tempname = temp.path {suffix: ".#{suffix}"}
                                converter.convert filename, @bitrate, tempname, (err) =>
                                        @_conversionDone err, cacheInstance, tempname


exports.FileConverterView = class FileConverterView
        constructor: (@log, @fileDatabase, @cache, @defaultType="mp3") ->
                @converter = new FileConverter @log, @cache

        view: (request, response) =>
                filename = request.params[0]
                if not @fileDatabase.exists filename
                        response.send "Not found", 404
                        return
                fullPath = @fileDatabase.getPath filename
                targetType = request.query.type or @defaultType
                @converter.convert targetType, fullPath, response
