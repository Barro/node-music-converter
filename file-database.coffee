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

        _cacheName: =>
                return "#{@cacheKey}.json"

        _cachePath: =>
                return path.join @cacheDir, @_cacheName()

        _checkCache: (callback) =>
                fs.exists @_cachePath(), (exists) =>
                        callback exists

        _createCache: (filedata, callback) =>
                fs.writeFile @_cachePath(), JSON.stringify(filedata), "utf-8", (err) =>
                        if err
                                callback "Failed to write cache to '#{@_cachePath}': #{err}"
                                return
                        @log.info "Created cache."
                        callback null

        open: (files, callback) =>
                @cacheKey = files.cacheKey
                @_createFileMap files
                @_checkCache (exists) =>
                        if exists
                                @log.info "Found cached file database."
                                callback null
                                return
                        @_createDatabase files, callback

        _createFileMap: (files) =>
                @filenames = {}
                for fileinfo in files.files
                        @filenames[fileinfo.filename] = true

        _createDatabase: (files, callback) =>
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

                for fileinfo in files.files
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
                @_createCache filedata, callback

        exists: (filename) =>
                return filename of @filenames

        getPath: (filename) =>
                return filename

        _getLocation: =>
                return "#{@cacheLocation}/#{@_cacheName()}"

        view: (request, response) =>
                location = @_getLocation()
                response.set "location", location
                response.send "Go to #{location}", 302
