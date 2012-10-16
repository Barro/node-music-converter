class RetryTimeouter
        constructor: (@minTimeout=1000, @maxTimeout=30000) ->
                @reset()

        increaseTimeout: =>
                timeout = @nextTimeout
                @nextTimeout = timeout + @lastTimeout
                if @nextTimeout > @maxTimeout
                        @nextTimeout = @maxTimeout
                @lastTimeout = timeout
                return timeout

        reset: =>
                @nextTimeout = @minTimeout
                @lastTimeout = @minTimeout


shuffledList = (list) ->
        shuffled = list.slice()
        for insert_position in [0..shuffled.length-1]
                swap_position = parseInt Math.random() * (shuffled.length - insert_position)
                swappable = shuffled[insert_position + swap_position]
                shuffled[insert_position + swap_position] = shuffled[insert_position]
                shuffled[insert_position] = swappable
        return shuffled


class SongQueue
        constructor: ->
                _.extend @, Backbone.Events
                @allSongs = []
                @visibleSongs = []
                @queuedSongs = []
                @playbackFiles = []
                @nextSong = null
                @nextLength = 0

        updateAll: (@allSongs) =>
                @trigger "updateAll", @allSongs

        updateVisible: (@visibleSongs) ->
                @playbackFiles = []
                @_removeRandom()
                @trigger "updateVisible", @visibleSongs

        length: =>
                length = @queuedSongs.length + @nextLength
                return length

        next: =>
                next = @peek()
                @nextSong = null
                @nextLength = 0
                if next != null
                        @trigger "next", next
                return next

        peek: =>
                if @nextSong != null
                        return @nextSong
                if @queuedSongs.length > 0
                        song = @queuedSongs.shift()
                        @nextSong = song
                        @nextLength = 1
                        return song

                if @visibleSongs.length == 0
                        if @allSongs.length == 0
                                return null
                        playbackCandidates = @allSongs
                else
                        playbackCandidates = @visibleSongs

                if @playbackFiles.length == 0
                        @playbackFiles = shuffledList playbackCandidates
                song = @playbackFiles.pop()
                @nextSong = song
                return song

        _removeRandom: =>
                # Replace current random song with the first queued song.
                if @nextSong != null and @nextLength == 0
                        @nextSong = null
                        @peek()

        add: (song) =>
                @queuedSongs.push song
                @_removeRandom()
                @trigger "add", song
                return @queuedSongs.length

        remove: (index) =>
                [removed] = @queuedSongs.splice(index, 1)
                @trigger "remove", song, index
                return removed

        show: =>
                return @queuedSongs


class PlaybackType
        constructor: (@request, @mime) ->


class Player
        constructor: (@playerElement, @timeouter, @playbackType) ->
                _.extend @, Backbone.Events
                @player = @playerElement.get(0)
                @currentSong = null
                @lastPreload = null
                @_bind()

        _bind: =>
                @playerElement.bind "pause", =>
                        @trigger "pause"
                @playerElement.bind "play", =>
                        @trigger "resume"
                @playerElement.bind "ended", =>
                        @trigger "ended"
                @playerElement.bind "volumechange", =>
                        @trigger "volumechange", @player.volume
                @playerElement.bind "timeupdate", =>
                        @trigger "timeupdate", @player.currentTime, @player.duration
                @playerElement.bind "durationchange", =>
                        @trigger "durationchange", @player.duration

        play: (song) =>
                @trigger "play", song
                [index, file] = song
                @playerElement.empty()
                encodedPath = encodeURIComponent file
                @playerElement.append "<source src=\"/file/#{encodedPath}?type=#{@playbackType.request}\" type='#{@playbackType.mime}' />"
                @player.load()
                @player.play()
                @currentSong = file

        preload: (song) =>
                if @lastPreload == song
                        return
                @lastPreload = song
                [index, file] = song
                encodedPath = encodeURIComponent file
                songPath = "/file/#{encodedPath}?type=#{@playbackType.request}"
                @trigger "preloadStart", song
                request = $.get(songPath)
                errorCallback = =>
                        setTimeout (=> @preload song),
                                @timeouter.increaseTimeout()
                request.error errorCallback
                request.success =>
                        @timeouter.reset()
                        @trigger "preloadOk", song

        togglePause: =>
                if @player.paused
                        @player.play()
                else
                        @player.pause()

        setVolume: (value) =>
                @player.volume = value

        getVolume: =>
                return @player.volume

        setPosition: (value) =>
                @player.currentTime = value

        getPosition: =>
                return @player.currentTime

        isPlaying: =>
                return not (@player.paused and @player.readyState == @player.HAVE_NOTHING)

viewTimeString = (total_seconds) ->
        hours = parseInt total_seconds / 3600
        remaining_seconds = total_seconds - hours * 3600
        minutes = parseInt remaining_seconds / 60
        remaining_seconds -= minutes * 60
        seconds = parseInt remaining_seconds
        hours_str = ""
        if hours > 0
                hours_str = "#{hours}:"

        time_str = hours_str + _.str.sprintf "%02d:%02d", minutes, seconds
        return time_str


PlayerView = (playerElement, player, songQueue) ->
        queueStatus = $("#queue-length", playerElement)
        songQueue.on "add", (song) ->
                queueStatus.text songQueue.length()
        songQueue.on "remove", (song) ->
                queueStatus.text songQueue.length()
        songQueue.on "next", (song) ->
                queueStatus.text songQueue.length()

        songQueue.on "next", (song) ->
                player.play song

        nextSongButton = $("#next", playerElement)
        nextSongButton.click ->
                songQueue.next()

        nextSongStatusElement = $("#status-next", playerElement)

        player.on "play", (song) ->
                player.preload songQueue.peek()
        songQueue.on "add", (song) ->
                player.preload songQueue.peek()

        lastPreloadSong = null
        player.on "preloadStart", (song) ->
                lastPreloadSong = song
                [index, file] = song
                nextSongStatusElement.text file
        player.on "preloadOk", (song) ->
                if song == lastPreloadSong
                        nextSongStatusElement.append "<span style='color: green'>&nbsp;✓</span>"

        playSongButton = $("#play-control", playerElement)
        playSongButton.click ->
                if player.isPlaying()
                        player.togglePause()
                else
                        queue.next()

        player.on "pause", ->
                playSongButton.text "Play"
        player.on "resume", ->
                playSongButton.text "Pause"
        player.on "ended", ->
                songQueue.next()

        currentSongStatusElement = $("#status-current", playerElement)
        player.on "play", (song) ->
                [index, file] = song
                currentSongStatusElement.text file

        volumeSlider = $(".volume-slider", playerElement)
        showVolume = (volume) ->
                volumeSlider.attr "value", volume * volumeSlider.attr "max"
                $(".volume-intensity", playerElement).text Math.round 100 * volume
        player.on "volumechange", (volume) ->
                showVolume volume

        showVolume player.getVolume()

        volumeSlider.bind "change", ->
                me = $(@)
                newVolume = me.val() / (me.attr("max") - me.attr("min"))
                player.setVolume newVolume

        positionSlider = $(".position-slider", playerElement)
        positionElement = $(".current-position", playerElement)
        player.on "timeupdate", (currentTime, duration) ->
                positionSlider.attr "value", currentTime
                positionElement.text viewTimeString currentTime

        positionSlider.bind "change", ->
                me = $(@)
                player.setPosition me.val()

        positionSlider.val player.getPosition()

        durationElement = $(".duration", playerElement)
        player.on "durationchange", (duration) ->
                positionSlider.attr "max", duration
                durationElement.text viewTimeString duration


QueueView = (queueElement, queueTable, queue, player) ->
        queue.on "next", (song) ->


        $("tr", queueElement).live "click", ->
                aPos = queueTable.fnGetPosition @
                iPos = aPos[0]

                song = queue.remove aPos
                queueTable.fnDeleteRow iPos
                player.play song


PlaylistView = (playlistElement, songData, player, queue, router) ->
        columns = [ { "bSearchable": false, "bVisible": false}, { "sTitle": "Song" } ]

        tableProperties =
                sScrollY: "450px"
                sDom: "frtiS"
                bDeferRender: true
                aaData: songData
                aoColumns: columns

        table = playlistElement.dataTable tableProperties

        table.on "filter", (event, settings) =>
                queue.updateVisible $.map settings.aiDisplay, (value, index) =>
                        return [ songData[value] ]

        hashChange = (songName) ->
                if (not player.isPlaying()) and (not songName?)
                        queue.next()
                        return
                if songName == player.currentSong
                        return
                $(songData).each (index, element) =>
                        [index, file] = element
                        if file == songName
                                player.play element
                                return false

        router.on "play", hashChange

        lastIndex = 0
        player.on "play", (song) ->
                oldRow = table.fnGetData lastIndex
                $(oldRow).remove(".playing")
                [newIndex, file] = song
                newRow = table.fnGetData newIndex
                $(newRow).add(".playing")
                router.navigate "/" + file

        $('tr', playlistElement).live "click", ->
                aData = table.fnGetData @
                song = aData
                queue.add song

class PlayerRouter extends Backbone.Router
        routes:
                "": 'playSong'
                "*filename": 'playSong'

        playSong: (filename) =>
                if filename?
                        filename = "/" + decodeURIComponent(filename)
                @trigger "play", filename


$(document).ready ->
        audio = new Audio();
        playbackType = null
        if (audio.canPlayType("audio/ogg"))
                playbackType = new PlaybackType "ogg", "audio/ogg"
        else if (audio.canPlayType("audio/mpeg"))
                playbackType = new PlaybackType "mp3", "audio/mpeg"
        else
                $("#status").text("Your browser does not support Vorbis or MP3")
                return

        playerContainer =  $("#player")
        playerJquery = $("audio", playerContainer)
        timeouter = new RetryTimeouter()
        playerInstance = new Player playerJquery, timeouter, playbackType
        songQueue = new SongQueue()

        PlayerView playerContainer, playerInstance, songQueue

        router = new PlayerRouter()

        $.getJSON "/files", (data) =>
                songData = []
                $.each data, (key, index) =>
                        songData.push([index, key])

                songQueue.updateAll songData

                PlaylistView $("#playlist"), songData, playerInstance, songQueue, router
                Backbone.history.start()
