fs = require 'fs'
lazy = require 'lazy'

exports.FileDatabaseView = class FileDatabaseView
        constructor: (@log) ->
                @filedata = []
                @filenames = {}

        open: (files) =>
                @filedata = []
                @filenames = {}

                for fileinfo in files
                        if not fileinfo.filename
                                continue
                        file =
                                filename: fileinfo.filename
                        if fileinfo.artist
                                file.artist = fileinfo.artist
                        if fileinfo.title
                                file.title = fileinfo.title
                        if fileinfo.album
                                file.album = fileinfo.album
                        @filedata.push file
                        @filenames[fileinfo.filename] = file

        exists: (filename) =>
                return filename of @filenames

        getPath: (filename) =>
                return filename

        view: (request, response) =>
                response.json @filedata
