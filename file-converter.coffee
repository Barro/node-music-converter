temp = require 'temp'
fs = require 'fs'
child_process = require 'child_process'

class VorbisConverter
        constructor: (@bitrate="160k") ->

        suffix: =>
                return "ogg"

        audioType: =>
                return "audio/ogg"

        mimeType: =>
                return "application/ogg"

        convert: (source, target, callback) =>
                options =
                        cwd: "/tmp/"
                ffmpeg = child_process.spawn "ffmpeg", ["-i", source, '-vn', '-acodec', 'libvorbis', '-ab', @bitrate, '-y', '-loglevel', 'quiet', target], options
                ffmpeg.on 'exit', (code) =>
                        if code != 0
                                callback "Failed file conversion."
                                return
                        callback null


class Mp3Converter
        constructor: (@bitrate="160k") ->

        suffix:  =>
                return "mp3"

        audioType: =>
                return "audio/mpeg"

        mimeType: =>
                return "audio/mpeg"

        convert: (source, target, callback) =>
                options =
                        cwd: "/tmp/"
                ffmpeg = child_process.spawn "ffmpeg", ["-i", source, '-vn', '-acodec', 'libmp3lame', '-ab', @bitrate, '-y', '-loglevel', 'quiet', target], options
                ffmpeg.on 'exit', (code) =>
                        if code != 0
                                callback "Failed file conversion."
                                return
                        callback null


class FileConverter
        constructor: ->
                @converters =
                        mp3: new Mp3Converter()
                        ogg: new VorbisConverter()

        _conversionDone: (err, response, tempname) =>
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
                        response.set('content-length', stats.size)
                        stream = fs.createReadStream tempname
                        stream.pipe response
                        stream.on "end", =>
                                fs.unlink tempname

        convert: (type, filename, response) =>
                if type not of @converters
                        response.send "I do not know how to convert to type #{type}.", 406
                        return
                converter = @converters[type]
                suffix = converter.suffix()
                response.set('content-type', converter.mimeType())
                response.set('cache-control', 'max-age=315360000, public')
                response.set('expires', (new Date(new Date().getTime() + 315360000*1000)).toUTCString());
                fs.stat filename, (statErr, stats) =>
                        if statErr
                                response.send "Failed to read original file name.", 500
                                return
                        response.set('last-modified', stats.mtime.toUTCString())

                        tempname = temp.path {suffix: ".#{suffix}"}
                        converter.convert filename, tempname, (err) =>
                                @_conversionDone err, response, tempname

exports.FileConverterView = class FileConverterView
        constructor: (@fileDatabase, @defaultType="mp3") ->
                @converter = new FileConverter()

        view: (request, response) =>
                filename = request.params[0]
                if not @fileDatabase.exists filename
                        response.send "Not found", 404
                        return
                fullPath = @fileDatabase.getPath filename
                targetType = request.query.type or @defaultType
                @converter.convert targetType, fullPath, response
