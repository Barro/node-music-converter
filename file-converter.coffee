child_process = require 'child_process'
crypto = require 'crypto'
fs = require 'fs'
path = require 'path'
temp = require 'temp'

# 1 minute of 160 kbps music.
FAILED_CONVERSION_IS_OK_SIZE = 60 * 160 * 1000 / 8

FFMPEG = "ffmpeg"

class AudioConverter
        _conversionDone: (target, code, callback) =>
                if code != 0
                        # We have failed file conversion. Let's check
                        # if the resulting file is large enough so that
                        # we can accept the conversion anyway.
                        fs.stat target, (err, stats) ->
                                if err
                                        callback "Failed file conversion. No file exists."
                                        return
                                if stats.size >= FAILED_CONVERSION_IS_OK_SIZE
                                        @_audioGain target, callback
                                        return
                                callback "Failed file conversion. Not enough data converted (#{stats.size} bytes)."
                        return
                @_audioGain target, callback


class OpusConverter extends AudioConverter
        suffix: =>
                return "opus"

        audioType: =>
                return "audio/opus"

        mimeType: =>
                return "audio/ogg"

        _audioGain: (target, callback) =>
                callback null

        convert: (source, bitrate, target, callback) =>
                options =
                        cwd: "/tmp/"
                ffmpeg = child_process.spawn FFMPEG, ["-i", source, '-vn', '-acodec', 'libopus', '-ab', bitrate, '-ar', '48000', '-ac', '2', '-loglevel', 'quiet', '-y', target], options
                ffmpeg.on 'exit', (code) =>
                        @_conversionDone target, code, callback


class VorbisConverter extends AudioConverter
        suffix: =>
                return "ogg"

        audioType: =>
                return "audio/ogg"

        mimeType: =>
                return "application/ogg"

        _audioGain: (target, callback) =>
                options =
                        cwd: "/tmp/"
                vorbisgain = child_process.spawn "vorbisgain", [target], options
                vorbisgain.on 'exit', (code) =>
                        callback null

        convert: (source, bitrate, target, callback) =>
                options =
                        cwd: "/tmp/"
                ffmpeg = child_process.spawn FFMPEG, ["-i", source, '-vn', '-acodec', 'libvorbis', '-ab', bitrate, '-ar', '48000', '-ac', '2', '-loglevel', 'quiet', '-y', target], options
                ffmpeg.on 'exit', (code) =>
                        @_conversionDone target, code, callback


class Mp3Converter extends AudioConverter
        suffix:  =>
                return "mp3"

        audioType: =>
                return "audio/mpeg"

        mimeType: =>
                return "audio/mpeg"

        _audioGain: (target, callback) =>
                options =
                        cwd: "/tmp/"
                mp3gain = child_process.spawn "mp3gain", [target], options
                mp3gain.on 'exit', (code) =>
                        callback null

        convert: (source, bitrate, target, callback) =>
                options =
                        cwd: "/tmp/"
                ffmpeg = child_process.spawn FFMPEG, ["-i", source, '-vn', '-acodec', 'libmp3lame', '-ab', bitrate, '-y', '-ar', '48000', '-ac', '2', '-loglevel', 'quiet', target], options
                ffmpeg.on 'exit', (code) =>
                        @_conversionDone target, code, callback


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

createPreloadCallback = (response) ->
        responseCallback = (headers, content, code) ->
                if code == 302
                        response.send content
                        return
                for header, value of headers
                        response.set header, value
                response.send content, code
        return responseCallback

createRedirectCallback = (response) ->
        responseCallback = (headers, content, code) ->
                for header, value of headers
                        response.set header, value
                response.send content, code
        return responseCallback

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
                @log.debug "Conversion finished."
                @_createResponse err, cacheInstance, tempname, (responseParams) =>
                        @log.debug "Sending response to clients: #{tempname}."
                        for response in @_ongoingConversions[cacheInstance.getKey()]
                                [content, code] = responseParams.data
                                response responseParams.headers, content, code
                        delete @_ongoingConversions[cacheInstance.getKey()]

        convert: (type, filename, responseCallback) =>
                @log.info "Starting conversion of '#{filename}' to type #{type}."
                if type not of @converters
                        responseCallback {}, "I do not know how to convert to type #{type}.", 406
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
                                responseCallback {location: location}, "Go to #{location}", 302
                                return

                        fs.stat filename, (statErr, stats) =>
                                if statErr
                                        responseCallback {}, "Failed to read original file name.", 500
                                        return

                                cacheKey = cacheInstance.getKey()
                                if cacheKey of @_ongoingConversions
                                        @log.debug "Adding #{cacheKey} to ongoing encodings."
                                        @_ongoingConversions[cacheKey].push responseCallback
                                        return
                                else
                                        @log.debug "Creating new ongoing encoding cache key #{cacheKey}."
                                        @_ongoingConversions[cacheKey] = [responseCallback]

                                tempname = temp.path {suffix: ".#{suffix}"}
                                converter.convert filename, @bitrate, tempname, (err) =>
                                        @_conversionDone err, cacheInstance, tempname


exports.FileConverterView = class FileConverterView
        constructor: (@log, @fileDatabase, @cache, @defaultType="mp3") ->
                @converter = new FileConverter @log, @cache

        _convert: (request, responseCallback) =>
                filename = request.params[0]
                if not @fileDatabase.exists filename
                        response.send "Not found", 404
                        return
                fullPath = @fileDatabase.getPath filename
                targetType = request.query.type or @defaultType
                @converter.convert targetType, fullPath, responseCallback

        preloadView: (request, response) =>
                responseCallback = createPreloadCallback response
                @_convert request, responseCallback

        redirectView: (request, response) =>
                responseCallback = createRedirectCallback response
                @_convert request, responseCallback