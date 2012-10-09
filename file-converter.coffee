child_process = require 'child_process'
crypto = require 'crypto'
fs = require 'fs'
path = require 'path'
temp = require 'temp'

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
                                callback "Failed file conversion."
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
                                callback "Failed file conversion."
                                return
                        callback null

class FileCacheInstance
        constructor: (@cache, @conversionParams) ->

        createCache: (convertedFilename, callback) =>
                return @cache.createCache convertedFilename, @conversionParams, callback

        getCached: (callback) =>
                return @cache.getCached @conversionParams, callback


exports.FileCache = class FileCache
        constructor: (@cachedir="/tmp", @cacheLocation) ->

        generate: (conversionParams) =>
                return new FileCacheInstance @, conversionParams

        _getDigest: (conversionParams) ->
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
                digest = @_getDigest conversionParams
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
                output = fs.createWriteStream filepath
                input.pipe output
                input.on "end", =>
                        callback null, @_getLocation conversionParams


class FileConverter
        constructor: (@cache)->
                @bitrate = "160k"
                @converters =
                        mp3: new Mp3Converter()
                        ogg: new VorbisConverter()

        _conversionDone: (err, cacheInstance, tempname, response) =>
                if err
                        fs.exists tempname, (exists) =>
                                if exists
                                        fs.unlink tempname
                                response.send "Failed to convert.", 500
                        return
                fs.stat tempname, (statErr, stats) =>
                        if statErr
                                response.send "Failed to read resulting file name.", 500
                                return
                        stream = fs.createReadStream tempname
                        stream.on "end", =>
                                fs.unlink tempname
                        cacheInstance.createCache tempname, (err, location) ->
                                response.set "location", location
                                response.send "Go to #{location}", 302

        convert: (type, filename, response) =>
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

                                tempname = temp.path {suffix: ".#{suffix}"}
                                converter.convert filename, @bitrate, tempname, (err) =>
                                        @_conversionDone err, cacheInstance, tempname, response


exports.FileConverterView = class FileConverterView
        constructor: (@fileDatabase, @cache, @defaultType="mp3") ->
                @converter = new FileConverter @cache

        view: (request, response) =>
                filename = request.params[0]
                if not @fileDatabase.exists filename
                        response.send "Not found", 404
                        return
                fullPath = @fileDatabase.getPath filename
                targetType = request.query.type or @defaultType
                @converter.convert targetType, fullPath, response
