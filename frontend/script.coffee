getPlayerObjects = ->
    playerContainer =  $("#player")
    playerJquery = $("audio", playerContainer)
    player = playerJquery.get(0)
    return {player: player, jquery: playerJquery}

SONGS = []
PLAYBACK_TYPES = {ogg: 'audio/ogg', mp3: 'audio/mpeg'}
PLAYBACK_TYPE = null
CURRENT_SONG = null
nextSong = null

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

RETRY_TIMEOUTER = new RetryTimeouter()

playHashSong = ->
        if document.location.hash.length <= 1
                return
        songName = document.location.hash.substr(1)
        if songName == CURRENT_SONG
                return
        playSong songName

playSong = (song) ->
        nextSong = song
        playRandomSong()

preloadSong = (successCallback) ->
    item = Math.floor(Math.random() * SONGS.length)
    nextSong = SONGS[item];
    nextStatus = $("#status-next")
    nextStatus.empty()
    nextStatus.text nextSong
    encodedPath = encodeURIComponent nextSong
    songPath = "/file/#{encodedPath}?type=#{PLAYBACK_TYPE}"

    request = $.get(songPath)
    errorCallback = =>
        setTimeout (-> preloadSong(successCallback)),
                RETRY_TIMEOUTER.increaseTimeout()

    request.error errorCallback
    request.success =>
        RETRY_TIMEOUTER.reset()
        if (successCallback)
            successCallback()
        else
            nextStatus.append("<span style='color: green'>&nbsp;✓</span>")


playRandomSong = ->
    song = nextSong
    CURRENT_SONG = song
    window.location = "#" + song
    $("#status").text(song)
    player = getPlayerObjects()
    player.player.pause()
    player.jquery.empty()

    audioType = PLAYBACK_TYPES[PLAYBACK_TYPE]
    encodedPath = encodeURIComponent(song)
    player.jquery.append("<source src=\"/file/#{encodedPath}?type=#{PLAYBACK_TYPE}\" type='#{audioType}' />")

    player.player.load()
    player.player.play()

    preloadSong()

$(document).ready ->
    audio = new Audio();
    if (audio.canPlayType("audio/ogg"))
        PLAYBACK_TYPE = "ogg"
    else if (audio.canPlayType("audio/mpeg"))
        PLAYBACK_TYPE = "mp3"
    else
        $("#status").text("Your browser does not support Vorbis or MP3")
        return

    player = getPlayerObjects()
    player.jquery.attr("controls", "controls")
    player.jquery.bind "ended", playRandomSong
    $(window).bind "hashchange", playHashSong

    $.getJSON "/files", (data) =>
        songData = []
        $.each data, (key, value) =>
            songData.push([key])
            SONGS.push(key)

        if document.location.hash.length > 1
                playHashSong()
        else
                preloadSong playRandomSong

        columns = [ { "sTitle": "Song" } ]

        tableProperties =
                sScrollY: "450px"
                sDom: "frtiS"
                bDeferRender: true
                aaData: songData
                aoColumns: columns

        oTable = $('#playlist').dataTable tableProperties
        $('#playlist tr').live "click", ->
                aData = oTable.fnGetData( this )
                iId = aData[0]
                playSong iId

    player.jquery.bind "abort", ->
        console.log "Aborted!"
        console.log player.player.error
        # setTimeout (-> playRandomSong()), RETRY_TIMEOUTER.increaseTimeout()
    player.jquery.bind "cancel", ->
        console.log "Canceled!"
    player.jquery.bind "invalid", ->
        console.log "Invalid!"
    player.jquery.bind "stalled", ->
        console.log "Stalled!"
    player.jquery.bind "waiting", ->
        console.log "Waiting!"
    player.jquery.bind "error", ->
        console.log "Error!"
    player.jquery.bind "change", ->
        console.log "change!"
    player.jquery.bind "loadeddata", ->
        console.log "loaddata!"

    player.jquery.bind "volumechange", ->
        slider = $(".volume-slider")
        slider.attr("value", player.player.volume * slider.attr("max"))
        $(".volume-intensity").text(Math.round(100 * player.player.volume))

    player.jquery.bind "pause", ->
        $("#play-control").text "Play"
    player.jquery.bind "playing", ->
        $("#play-control").text "Pause"

    $("#next").click ->
        playRandomSong()

    $("#play-control").click ->
        if (player.player.paused)
            player.player.play()
        else
            player.player.pause()

    slider = $(".volume-slider")
    slider.attr("value", player.player.volume * slider.attr("max"))
    $(".volume-intensity").text(Math.round(100 * player.player.volume))
    slider.change ->
        me = $(@)
        newVolume = me.val() / (me.attr("max") - me.attr("min"))
        player.player.volume = newVolume
