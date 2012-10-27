crypto = require 'crypto'
fs = require 'fs'
path = require "path"
lazy = require 'lazy'
unorm = require 'unorm'

stripEmptyItems = (list) ->
        while list[list.length - 1] == ""
                list.pop()
        return list

exports.FileDatabaseView = class FileDatabaseView
        constructor: (@cacheDir, @cacheLocation, @log) ->
                @filenames = {}
                @cacheKey = ""

        _cacheName: (type) =>
                return "#{@cacheKey}.#{type}.json"

        _cachePath: (type) =>
                return path.join @cacheDir, @_cacheName(type)

        _readCacheData: (filename, callback) =>
                stream = fs.ReadStream filename
                stream.on "error", (err) =>
                        @log.info "Failed to read playlist cache: #{err}."
                        callback err
                fileDataStr = ""
                stream.on "data", (data) ->
                        fileDataStr += data
                stream.on "end", ->
                        fileData = JSON.parse fileDataStr
                        callback null, fileData

        _assignFileinfo: (fileData, callback) =>
                @filenames = fileData.filenames
                @cacheKey = fileData.cacheKey
                callback null


        _createChecksum: (filename, callback) =>
                hash = crypto.createHash "sha512"
                stream = fs.ReadStream filename
                stream.on "error", (err) ->
                        @log.error "Failed to open playlist: #{err}."
                        callback err
                stream.on "data", (data) ->
                        hash.update data
                stream.on "end", ->
                        checksum = hash.digest "hex"
                        callback null, checksum

        _processCacheData: (err, parser, filename, fileData, callback) =>
                if not err
                        @log.info "Loaded cached file."
                        @filenames = @_createFileMap fileData
                        callback null
                        return
                parser.parse filename, (err, files) =>
                        if err
                                callback err
                                return
                        @filenames = @_createFileMap files
                        @_createCache files, callback

        _createCache: (files, callback) =>
                filesFilename = @_cachePath "filedata"
                fs.writeFile filesFilename, JSON.stringify(files), "utf-8", (err) =>
                        if err
                                @log.warn "Failed to create file info cache file: #{filesFilename}."

                playlistData = @_createPlayerDatabase files
                playlistFilename = @_cachePath "playlist"
                fs.writeFile playlistFilename, JSON.stringify(playlistData), "utf-8", (err) =>
                        if err
                                @log.warn "Failed to create playlist cache file: #{playlistFilename}."
                        callback null, files

        open: (parser, filename, callback) =>
                @_createChecksum filename, (err, checksum) =>
                        if err
                                callback err
                                return
                        @cacheKey = checksum
                        @_readCacheData @_cachePath("filedata"), (err, fileData) =>
                                @_processCacheData err, parser, filename, fileData, callback

        _createFileMap: (files) =>
                filenames = {}
                # TODO unicode normalization for file names.
                for fileinfo in files
                        filenames[fileinfo.filename] = fileinfo.filename
                return filenames

        _createPlayerDatabase: (files) =>
                @log.info "Creating a new file database."
                filedata = {directories: [], fields: [], files: []}
                directoryId = 0
                directoryIds = {"": 0}
                shortFiles = []
                fields = ['filename', 'title', 'artist', 'album']
                directories = [""]

                shortenFilename = (filename) ->
                        parts = filename.split "/"
                        # Remove filename
                        basename = parts.pop()
                        if parts.length == 0
                                return basename

                        firstPart = parts.shift()
                        fullDirectory = firstPart
                        if firstPart of directoryIds
                                currentId = directoryIds[firstPart]
                        else
                                currentId = directories.length
                                directories.push firstPart
                                directoryIds[fullDirectory] = firstPart

                        for part in parts
                                fullDirectory += "/#{part}"
                                if fullDirectory of directoryIds
                                        currentId = directoryIds[fullDirectory]
                                else
                                        directories.push "#{currentId}/#{part}"
                                        currentId = directories.length - 1
                                        directoryIds[fullDirectory] = currentId
                        return "#{currentId}/#{basename}"

                for fileinfo in files
                        if not fileinfo.filename
                                continue

                        file = [shortenFilename fileinfo.filename]

                        if fileinfo.title
                                file.push unorm.nfkd fileinfo.title
                        else
                                file.push ""
                        if fileinfo.artist
                                file.push unorm.nfkd fileinfo.artist
                        else
                                file.push ""
                        if fileinfo.album
                                file.push unorm.nfkd fileinfo.album
                        else
                                file.push ""
                        file = stripEmptyItems file
                        shortFiles.push file
                filedata.directories = directories
                filedata.files = shortFiles
                filedata.fields = fields
                @log.info "Finished reading file data."
                return filedata

        exists: (filename) =>
                return filename of @filenames

        getPath: (filename) =>
                return @filenames[filename]

        _getLocation: =>
                return "#{@cacheLocation}/#{@_cacheName('playlist')}"

        view: (request, response) =>
                location = @_getLocation()
                response.set "location", location
                response.send "Go to #{location}", 302
