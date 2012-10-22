fs = require 'fs'
lazy = require 'lazy'
unorm = require 'unorm'

stripEmptyItems = (list) ->
        while list[list.length - 1] == ""
                list.pop()
        return list

exports.FileDatabaseView = class FileDatabaseView
        constructor: (@log) ->
                @filedata = []
                @filenames = {}

        open: (files) =>
                @filedata = {directories: [], fields: [], files: []}
                @filenames = {}
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
                        @filenames[fileinfo.filename] = file
                @filedata.directories = directories
                @filedata.files = shortFiles
                @filedata.fields = fields

        exists: (filename) =>
                return filename of @filenames

        getPath: (filename) =>
                return filename

        view: (request, response) =>
                response.json @filedata
