getPlayerObjects = ->
    playerContainer =  $("#player")
    playerJquery = $("audio", playerContainer)
    player = playerJquery.get(0)
    return {player: player, jquery: playerJquery}

SONGS = []
PLAYBACK_TYPES = {ogg: 'audio/ogg', mp3: 'audio/mpeg'}
PLAYBACK_TYPE = null
nextSong = null

playHashSong = ->
        songName = document.location.hash.substr(1)
        playSong songName

playSong = (song) ->
        nextSong = song
        playRandomSong()

preloadSong = (successCallback) ->
    item = Math.floor(Math.random() * SONGS.length)
    nextSong = SONGS[item];
    nextStatus = $("#status-next")
    nextStatus.empty()
    nextStatus.text(nextSong)
    encodedPath = encodeURIComponent(nextSong)
    songPath = "/file/#{encodedPath}?type=#{PLAYBACK_TYPE}"
    request = $.get(songPath)
    errorCallback = =>
        setTimeout (-> preloadSong(successCallback)), 1000
    request.error errorCallback
    request.success =>
        if (successCallback)
            successCallback()
        else
            nextStatus.append("<span style='color: green'>&nbsp;✓</span>")

    # // var player = new Audio();
    # // var playerContainer = $("#player-preloaded");
    # // playerContainer.empty();
    # // playerContainer.append(player);
    # // var playerJquery = $(player);
    # // var encodedPath = encodeURIComponent(nextSong);
    # // playerJquery.append("<source src='/file/" + encodedPath + "?type=ogg' type='audio/ogg' />");
    # // playerJquery.append("<source src='/file/" + encodedPath + "?type=mp3' type='audio/mpeg' />");
    # // playerJquery.attr("preload", "auto");

playRandomSong = ->
    song = nextSong
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
    $(document).bind "hashchange", playHashSong

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

    player.player.onpause = ->
        $("#play-control").text "Play"
    player.player.onplaying = ->
        $("#play-control").text "Pause"

    $("#next").click ->
        playRandomSong()

    $("#play-control").click ->
        if (player.player.paused)
            player.player.play()
        else
            player.player.pause()
