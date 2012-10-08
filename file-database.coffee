fs = require 'fs'
lazy = require 'lazy'

exports.FileDatabaseView = class FileDatabaseView
        constructor: () ->
                @filelist = {}

        open: (filelistFile) =>
                filereader = new lazy fs.createReadStream(filelistFile)
                filereader.lines.forEach (filenameBuffer) =>
                        filename = filenameBuffer.toString "utf-8"
                        @filelist[filename] = true

        exists: (filename) =>
                return filename of @filelist

        getPath: (filename) =>
                return filename

        view: (request, response) =>
                response.json @filelist
