PRELOAD_COUNT = 20
# Even though all songs can not be converted in 10 seconds, this at least
# ensures that a long running song will not completely destroy the preload
# performance.
PRELOAD_WAIT_TIMEOUT = 10 * 1000

RESIZE_UPDATE_DELAY = 500
SEARCH_UPDATE_PRELOAD_DELAY = 2000
CONVERSION_WAIT_TIMEOUT = 180 * 1000

MINIMUM_PROGRESS_FILES = 10000
FILE_PROGRESS_UPDATE_INTERVAL = 2000

PLAYLIST_BASIC_COLUMNS = []

MINIMUM_RETRY_TIMEOUT = 500
MAXIMUM_RETRY_TIMEOUT = 5000

VOLUME_STEPS = 100

PLAYLIST_BASIC_COLUMNS.push
  bSearchable: false
  sTitle: "Title"
  bSortable: false
  sClass: "title"
  sWidth: "300px"

PLAYLIST_BASIC_COLUMNS.push
  bSearchable: false
  sTitle: "Album"
  bSortable: false
  sClass: "album"
  sWidth: "300px"

PLAYLIST_BASIC_COLUMNS.push
  bSearchable: false
  sTitle: "Artist"
  bSortable: false
  sClass: "artist"
  sWidth: "300px"

simpleNormalizeName = (name) ->
  return name.replace /\s+/g, "-"

class RetryTimeouter
  constructor: (@minTimeout=MINIMUM_RETRY_TIMEOUT, @maxTimeout=MAXIMUM_RETRY_TIMEOUT) ->
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


class Preloader
  constructor: (@queue, @playbackType, @preloadCount) ->
    @preloaded = {}
    @nextPreloads = []
    @ongoingPreloads = {}

  _preloadSong: =>
    if @nextPreloads.length == 0
      return
    if _.keys(@ongoingPreloads).length != 0
      return
    song = @nextPreloads.shift()
    encodedPath = encodeURIComponent songFilename song
    preloadSource = "preload/#{encodedPath}?type=#{@playbackType.request}"
    @ongoingPreloads[songFilename song] = new Date()
    request = $.ajax preloadSource,
      type: "GET"
      timeout: PRELOAD_WAIT_TIMEOUT
    preloadCallback = =>
      @preloaded[songFilename song] = new Date()
      delete @ongoingPreloads[songFilename song]
      if @nextPreloads.length == 0
        return
      nextSong = @nextPreloads.shift()
      @_preloadSong nextSong
    request.error preloadCallback
    request.success preloadCallback

  updatePreload: =>
    allSongs = @queue.playbackQueue()
    preloadSongs = [@queue.peek()].concat(allSongs[0..].reverse())
    @nextPreloads = []
    totalPreloads = 0
    for song in preloadSongs
      if totalPreloads == @preloadCount
        break
      if songFilename(song) in @preloaded
        continue
      totalPreloads++
      @nextPreloads.push song
    @_preloadSong()


class SongQueue
  constructor: (@storage) ->
    _.extend @, Backbone.Events
    @allSongs = []
    @visibleSongs = []
    if @storage.queue
      @queuedSongs = JSON.parse @storage.queue
    else
      @queuedSongs = []
    @playbackFiles = []
    @nextSong = null
    @nextLength = 0

  fullQueue: =>
    if @nextLength == 0
      return @queuedSongs
    fullQueue = [@nextSong]
    for song in @queuedSongs
      fullQueue.push song
    return fullQueue

  updateAll: (@allSongs) =>
    @trigger "updateAll", @allSongs
    @trigger "queueChange"

  updateVisible: (newVisibleSongs) ->
    if @visibleSongs == newVisibleSongs
      return
    @visibleSongs = newVisibleSongs
    @playbackFiles = []
    @_removeRandom()
    @trigger "updateVisible", @visibleSongs
    @trigger "queueChange"

  length: =>
    return @fullQueue().length

  next: =>
    next = @peek()
    @clearNext()
    if next != null
      @trigger "next", next
      @trigger "queueChange"
    return next

  clearNext: =>
    @nextSong = null
    @nextLength = 0
    @storage.queue = JSON.stringify @fullQueue()

  peek: =>
    if @nextSong != null
      return @nextSong
    if @queuedSongs.length > 0
      @storage.queue = JSON.stringify @fullQueue()
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
    @storage.queue = JSON.stringify @fullQueue()
    @_removeRandom()
    @trigger "add", song
    @trigger "queueChange"
    return @queuedSongs.length

  remove: (index) =>
    queue = @fullQueue()
    @clearNext()
    [removed] = queue.splice(index, 1)
    @storage.queue = JSON.stringify queue
    @queuedSongs = queue
    @trigger "remove", removed, index
    @trigger "queueChange"
    return removed

  show: =>
    return @queuedSongs

  playbackQueue: =>
    return @playbackFiles


class PlaybackType
  constructor: (@request, @mime) ->


class Player
  constructor: (@playerElement, @preloadElement, @storage, @timeouter, @playbackType) ->
    _.extend @, Backbone.Events
    @lastSource = null

    @player = @playerElement.get(0)
    @preloadPlayer = @preloadElement.get(0)
    @continuePosition = 0
    @preloads = {}
    @_bind()
    if @storage.volume
      @setVolume @storage.volume
    @startedPlaying = false
    if @storage.currentSong
      try
        @currentSong = jsonToSong @storage.currentSong
        @lastPosition = parseInt @storage.continuePosition
        @resumePlaying()
      catch error
        @currentSong = null
    else
      @currentSong = null
      @lastPosition = 0

  _bind: =>
    @playerElement.bind "pause", =>
      @trigger "pause"
    @playerElement.bind "play", =>
      @trigger "resume"
    @playerElement.bind "ended", =>
      @trigger "ended"
    @playerElement.bind "volumechange", =>
      @storage.volume = @player.volume
      @trigger "volumechange", @player.volume
    @playerElement.bind "timeupdate", =>
      @storage.continuePosition = @player.currentTime
      @trigger "timeupdate", @player.currentTime, @player.duration
    @playerElement.bind "durationchange", =>
      @trigger "durationchange", @player.duration

    @playerElement.bind "loadeddata", =>
      # Prevent invalid songs playing when going forward on
      # playlist faster than songs load.
      currentSource = $("source", @playerElement).attr "src"
      # console.log "last source: #{@lastSource}"
      # console.log "player source: #{currentSource}"
      if currentSource != @lastSource
        # console.log "returned"
        return
      @startedPlaying = true
      if @continuePosition
        @player.currentTime = @continuePosition
        @continuePosition = 0
      @player.play()
      @trigger "play", @currentSong

  resumePlaying: =>
    @continuePosition = @lastPosition
    @play @currentSong

  play: (song) =>
    @playerElement.empty()
    encodedPath = encodeURIComponent songFilename song
    songSource = "file/#{encodedPath}?type=#{@playbackType.request}"
    @playerElement.append "<source src=\"#{songSource}\" type='#{@playbackType.mime}' />"
    @player.load()
    @lastSource = songSource
    # console.log "last source: #{@lastSource}"
    @currentSong = song
    @storage.currentSong = JSON.stringify songToJson @currentSong
    # Preload the currently playing song to handle cases where we
    # fail to play the requested song. As audio element does not
    # send any events on failed playback, we need to use another
    # trick to detect failures.
    @preload song, false
    @trigger "preparePlay", song

  preload: (song, react=true) =>
    if not song
      return
    if songFilename(song) of @preloads
      return
    @preloads[songFilename song] = new Date()
    encodedPath = encodeURIComponent songFilename song
    songPath = "file/#{encodedPath}?type=#{@playbackType.request}"
    @trigger "preloadStart", song, react

    successCallback = (song) =>
      delete @preloads[songFilename song]
      @timeouter.reset()

      @preloadElement.empty()
      source = @preloadElement.append "<source type='#{@playbackType.mime}' />"
      source.attr "src", songPath
      @preloadPlayer.load()

      @trigger "preloadOk", song, react

    request = $.ajax songPath,
      type: "HEAD"
      timeout: CONVERSION_WAIT_TIMEOUT
    failCallback = (song) =>
      @trigger "preloadFailed", song, react
    errorCallback = (song) =>
      delete @preloads[songFilename song]
      setTimeout (=> failCallback song), @timeouter.increaseTimeout()
    request.error (xhr, textStatus, errorThrown) =>
      # 302 redirect in Opera
      if errorThrown == "Moved Temporarily"
        successCallback song
      else
        errorCallback song
    request.success (=> successCallback song)

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
    return @player.networkState != @player.NETWORK_NO_SOURCE


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
  queueStatus.text songQueue.length()
  songQueue.on "add", (song) ->
    # console.log "add -> queuestatus"
    queueStatus.text songQueue.length()
  songQueue.on "remove", (song, index) ->
    # console.log "remove -> queuestatus"
    queueStatus.text songQueue.length()
  songQueue.on "next", (song) ->
    # console.log "next -> queuestatus"
    queueStatus.text songQueue.length()

  songQueue.on "next", (song) ->
    # console.log "next -> player.play"
    player.play song

  player.on "preloadFailed", (song, react) ->
    # Preloads may fail when player has the next song in cache
    # and is disconnected from the network before the
    # currently playing song is finished. This will trigger
    # playback of the cached song and also the preload of the
    # same song. But if the playback startup succeeds and preload
    # fails, the song will still play, but preloadFailed event
    # will also be triggered for that song. Therefore we'll check
    # if that song is playing before we decide to skip to the
    # next song in the queue.
    if song == player.currentSong and not player.isPlaying()
      songQueue.next()

  nextSongButton = $("#next", playerElement)
  nextSongButton.click ->
    # console.log "nextSongButton.click -> next"
    songQueue.next()

  nextSongStatusElement = $("#preload-status", playerElement)

  player.on "play", (song) ->
    # console.log "player.play preload"
    player.preload songQueue.peek(), true

  lastPreloadSong = null
  player.on "preloadStart", (song, react) ->
    # console.log "player.preloadStart #{react} #{song.filename}"
    if not react
      # console.log "player.preloadStart -> noreact"
      return
    lastPreloadSong = song
    newsong = $("<span class='notloaded'>✘</span>")
    newsong.attr "title", "#{songTitle(song)} / #{songAlbum(song)} / #{songArtist(song)} / #{songFilename song}"
    nextSongStatusElement.html newsong

  player.on "preloadFailed", (song, react) ->
    songQueue.clearNext()
    newSong = songQueue.peek()
    player.preload newSong, react

  player.on "preloadOk", (song, react) ->
    if not react
      return
    if song == lastPreloadSong
      newsong = $(".notloaded", nextSongStatusElement)
      newsong.removeClass "notloaded"
      newsong.addClass "loaded"
      newsong.text "✓"

    if not player.isPlaying()
      player.play song

  preloadOnQueueChange = ->
    if songQueue.peek() == lastPreloadSong
      return
    player.preload songQueue.peek(), true

  songQueue.on "add", preloadOnQueueChange
  songQueue.on "remove", preloadOnQueueChange
  songQueue.on "updateAll", preloadOnQueueChange

  lastUpdateDelayId = 0
  delayedQueueChangePreload = ->
    lastUpdateDelayId++
    updateDelayId = lastUpdateDelayId
    updateOnChange = (delayId) ->
      # console.log "update on change"
      if updateDelayId != lastUpdateDelayId
        # console.log "not newest"
        return
      preloadOnQueueChange()
    setTimeout updateOnChange, SEARCH_UPDATE_PRELOAD_DELAY
  songQueue.on "updateVisible", delayedQueueChangePreload

  playSongButton = $("#play-control", playerElement)
  playSongButton.click ->
    # console.log "playSongButton.click"
    if player.isPlaying()
      # console.log "playSongButton.click -> isPlaying"
      player.togglePause()
    else
      # console.log "playSongButton.click -> queueNext"
      songQueue.next()

  player.on "pause", ->
    playSongButton.text "Play"
  player.on "resume", ->
    playSongButton.text "Pause"
  player.on "ended", ->
    # console.log "player.ended -> next"
    songQueue.next()

  currentSongStatusElement = $("#status-current", playerElement)
  artistElement = $("#artist", currentSongStatusElement)
  albumElement = $("#album", currentSongStatusElement)
  titleElement = $("#title", currentSongStatusElement)
  player.on "preparePlay", (song) ->
    currentSongStatusElement.attr "title", songFilename(song)
    artistElement.text songArtist(song)
    albumElement.text songAlbum(song)
    titleElement.text songTitle(song)

  artistElement.click ->
    searchValue = "artist:#{simpleNormalizeName artistElement.text()}-"
    $("#search").val(searchValue).change()
  albumElement.click ->
    searchValue = "album:#{simpleNormalizeName albumElement.text()}-"
    $("#search").val(searchValue).change()
  titleElement.click ->
    if player.currentSong
      songQueue.add player.currentSong

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
  player.on "preparePlay", (song) ->
    durationElement.text viewTimeString 0

songToQueueRow = (song) ->
  return [songTitle(song), songAlbum(song), songArtist(song)]

initialPlayerComponentsHeight = (document) ->

QueueView = (queueButton, queueElement, queue, player, playlistElement, viewport) ->
  columns = []

  for column in PLAYLIST_BASIC_COLUMNS
    columns.push column

  queueData = []
  for song in queue.fullQueue()
    queueData.push songToQueueRow song

  table = queueElement.dataTable
    sScrollY: "#{viewport.playlistHeight}px"
    sScrollX: "100%"
    sScrollXInner: "100%"
    bScrollCollapse: false
    bAutoWidth: false
    sDom: "rtiS"
    bDeferRender: true
    aaData: queueData
    aoColumns: columns
    bFilter: false
    bSort: false
    aaSorting: []

  queueWrapper = $("#queue_wrapper")
  queueWrapper.hide()

  queue.on "add", (song) ->
    table.fnAddData songToQueueRow song

  queue.on "next", (song) ->
    data = table.fnGetData()
    if data.length > 0
      table.fnDeleteRow 0

  queue.on "remove", (song, index) ->
    table.fnDeleteRow index

  queueButton.on "click", ->
    $("#playlist_wrapper").toggle()
    queueWrapper.toggle()
    if queueWrapper.is ":visible"
      queueButton.text "Hide queue"
    else
      queueButton.text "Show queue"

  $(queueElement).on "click", "tr", ->
    iPos = table.fnGetPosition @
    song = queue.remove iPos
    player.play song

PlaylistView = (playlistElement, songData, player, queue, router, search, viewport) ->
  columns = []

  columns.push
    bSearchable: false
    bVisible: false
    bSortable: false
    sWidth: "1px"

  for column in PLAYLIST_BASIC_COLUMNS
    columns.push column

  tableData = []
  for song in songData
    tableData.push(song.data)

  table = playlistElement.dataTable
    sScrollY: "#{viewport.playlistHeight}px"
    sScrollX: "100%"
    sScrollXInner: "100%"
    bScrollCollapse: false
    bAutoWidth: false
    sDom: "rtiS"
    bDeferRender: true
    aaData: tableData
    aoColumns: columns
    bFilter: false
    bSort: false
    aaSorting: []

  table.on "filter", (event, settings) =>
    visible = []
    for songIndex in settings.aiDisplay
      visible.push songData[songIndex]
    queue.updateVisible visible

  lastHashChange = null

  # TODO forward/backward does not work due to resumption functionality.
  hashChange = (songName) ->
    if lastHashChange == songName
      return
    lastHashChange = songName

    # Front page for the first time:
    if not player.startedPlaying
      if player.currentSong and (not songName? or songFilename(player.currentSong) == songName)
        # console.log "resume playing"
        player.resumePlaying()
      else
        # console.log "next song"
        queue.next()
      return

    # Hash change while player has already started playing
    # something.
    if player.startedPlaying
      if songName == songFilename(player.currentSong)
        # console.log "current song"
        return

    # Cases where the song is selected through the hash element
    # change.
    $(songData).each (index, element) =>
      song = songData[index]
      if songFilename(song) == songName
        # console.log "playing"
        player.play song
        queue.clearNext()
        return false

  router.on "play", hashChange

  # TODO highlight currently playing song
  # lastIndex = 0
  # player.on "play", (song) ->
  #   oldRow = table.fnGetData lastIndex
  #   $(oldRow).remove(".playing")
  #   [newIndex, file] = song
  #   newRow = table.fnGetData newIndex
  #   $(newRow).add(".playing")

  lastSong = null

  player.on "preparePlay", (song) ->
    if lastHashChange != songFilename(song)
      router.navigate "/" + songFilename(song)

  previousRow = null
  focusRow = (song) ->
    if previousRow
      $(previousRow).removeClass "playing"
    row = table.fnGetNodes songIndex(song)
    $(row).addClass "playing"
    previousRow = row

  # Focus on the current song.
  player.on "preparePlay", focusRow
  if player.currentSong
    focusRow player.currentSong

  $(playlistElement).on "click", "tr", ->
    aData = table.fnGetData @
    [index, data...] = aData
    queue.add songData[index]

  table.fnFilter = (string) ->
    oSettings = @fnSettings()
    # Tell the draw function we have been filtering
    search.search string, (result) =>
      oSettings.bFiltered = true
      oSettings.aiDisplay = result
      $(oSettings.oInstance).trigger('filter', oSettings);
      # Redraw the table
      oSettings._iDisplayStart = 0;
      @_fnCalculateEnd oSettings
      @_fnDraw oSettings

  if search.lastSearch
    $("#search").val search.lastSearch
    table.fnFilter search.lastSearch
  doSearch = ->
    searchValue = $("#search").val()
    if searchValue == search.lastSearch
      return
    table.fnFilter searchValue
  $("#search").keyup doSearch
  $("#search").change doSearch

  # viewport.on "resize", (width, height) ->
  # oSettings = table.fnSettings()
  # oSettings.oScroll.sY = viewport.playlistHeight
  # table.fnDraw();

class PlayerRouter extends Backbone.Router
  routes:
    "": 'playSong'
    "*filename": 'playSong'

  playSong: (filename) =>
    if filename?
      filename = "/" + decodeURIComponent(filename)
    @trigger "play", filename


class Search
  constructor: (@worker, @storage) ->
    _.extend @, Backbone.Events
    @worker.onmessage = (event) =>
      @_handle event.data
    @searchId = 0
    @searchCallbacks = {}
    if @storage.lastSearch
      @lastSearch = @storage.lastSearch
    else
      @lastSearch = ''

  _handle: (data) =>
    if data.type == "initialize"
      @_handleInitialize()
    else if data.type == "result"
      @_handleResult data
    else if data.type == "message"
      console.log data.message
    else
      throw new Error "Unknown message type #{data.type}"

  _handleInitialize: =>
    # Handle case where we initialize search in the page load.
    if @searchId of @searchCallbacks
      callback = @searchCallbacks[@searchId]
      @searchCallbacks[@searchId] = (matches) =>
        try
          callback matches
        catch e
          console.log e
        @trigger "initialize"
    else
      @trigger "initialize"

  _handleResult: (result) =>
    callback = @searchCallbacks[result.searchId]
    delete @searchCallbacks[result.searchId]
    # Only accept results from the latest search.
    if result.searchId == @searchId
      matches = result.matches
      callback matches
      @trigger "result", result

  initialize: (data) =>
    message =
      type: "initialize"
      data: data
    @worker.postMessage message

  search: (string, callback) =>
    @searchId++
    @searchCallbacks[@searchId] = callback
    @lastSearch = string
    @storage.lastSearch = string
    @worker.postMessage {type: "search", searchId: @searchId, value: string}


HotkeysView = (player, queue, pauseElement, nextElement, toggleQueueElement, searchField) ->
  $(document).bind "keypress.b", ->
    queue.next()
    nextElement.focus()
  $(document).bind "keypress.x", ->
    player.togglePause()
    pauseElement.focus()
  $(document).bind "keypress.q", ->
    toggleQueueElement.click()
  $(document).bind "keypress.j", ->
    searchField.focus()
    return false
  unfocusSearch = ->
    searchField.blur()
    return false
  $(searchField).bind "keyup.return", unfocusSearch
  $(searchField).bind "keyup.esc", unfocusSearch

  # TODO Might be a better idea to have a relative volume control instead
  # of absolute.
  $(document).bind "keypress.+", ->
    currentVolume = Math.round VOLUME_STEPS * player.getVolume()
    newVolume = Math.min(VOLUME_STEPS, currentVolume + 1)
    player.setVolume newVolume / VOLUME_STEPS
  $(document).bind "keypress.-", ->
    currentVolume = Math.round VOLUME_STEPS * player.getVolume()
    newVolume = Math.max(0, currentVolume - 1)
    player.setVolume newVolume / VOLUME_STEPS


class SongSearch
  constructor: (fileObject) ->
    if fileObject.filename_normalized
      [directory, basename] = fileObject.filename.split("/")
      @filename = "#{directory}/#{fileObject.filename_normalized}"
    else
      @filename = fileObject.filename
    @title = fileObject.title_normalized or fileObject.title
    @album = fileObject.album_normalized or fileObject.album
    @artist = fileObject.artist_normalized or fileObject.artist


get_directory = (directories, filename) ->
  directoryName = ""
  if filename.indexOf("/") != -1
    [parentStr, basefile] = filename.split "/"
    parent = parseInt parentStr
    basename = directoryName
    while parent != 0
      [parentStr, basename] = directories[parent].split "/"
      if parentStr == ""
        parent = 0
      else
        parent = parseInt parentStr
      directoryName = "#{basename}/#{directoryName}"
  return "/#{directoryName}"

UNKNOWN_STRING = "UNKNOWN"


class SongDisplay
  # @data can be shared with datatables.
  constructor: (@directories, @filename, @data) ->


createSong = (fields, index, directories, fileinfo) ->

  # This guess is often wrong as not everything is
  # organized like this, but this is usually better
  # than showing nothing.
  filename = fileinfo[fields['filename']]
  title = fileinfo[fields['title']]
  album = fileinfo[fields['album']]
  artist = fileinfo[fields['artist']]
  if not (title and album and artist)
    filenameParts = filename.split "/"
    [artistPart, albumPart, titlePart] = filenameParts[(filenameParts.length - 3)..(filenameParts.length - 1)]
  data = [index,
    artist or artistPart or UNKNOWN_STRING,
    album or albumPart or UNKNOWN_STRING,
    title or titlePart or UNKNOWN_STRING]
  return new SongDisplay directories, filename, data

songIndex = (song) ->
  return song.data[0]


songTitle = (song) ->
  return song.data[1]


songAlbum = (song) ->
  return song.data[2]


songArtist = (song) ->
  return song.data[3]


songFilename = (song) ->
  directoryName = get_directory song.directories, song.filename
  [directory, basename] = song.filename.split "/"
  if not basename
    basename = song.filename
  return "#{directoryName}#{basename}"


jsonToSong = (json_data) ->
  song = new SongDisplay [], "", {}
  for key, value in JSON.parse json_data
    song[key] = value
  return song


songToJson = (song) ->
  directoryName = ""
  basename = song.filename
  if song.filename.indexOf("/") != -1
    [directory, basename] = song.filename.split "/"
    directoryName = get_directory song.directories, song.filename
  data =
    data: [0, songTitle(song), songAlbum(song), songArtist(song)]
    directories: [directoryName]
    filename: "0/#{basename}"
  return data


class Viewport
  constructor: (@document) ->
    _.extend @, Backbone.Events
    @decoratorHeight = $("#content", @document).height()
    @playlistHeight = $(@document).height() - @decoratorHeight
    $(".remove-after-height-calculation", @document).remove()
    @lastSizeUpdate = 0

  _updateHeight: =>
    @playlistHeight = $(@document).height() - @decoratorHeight
    @trigger "resize"

  _bind: =>
    $(@document).resize =>
      @lastSizeUpdate++
      currentUpdate = @lastSizeUpdate
      updateCallback = =>
        if @lastSizeUpdate != currentUpdate
          return
        @_updateHeight()
      setTimeout updateCallback, RESIZE_UPDATE_DELAY

START_LOAD = (new Date()).getTime()

SEARCH_WORKER = new Worker "/search.js"

$(document).ready ->
  $('[data-toggle=tooltip]').tooltip({delay: { show: 400, hide: 100 }})

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
  playerElement = $(".player", playerContainer)
  preloadElement = $(".preload-player", playerContainer)
  timeouter = new RetryTimeouter()
  playerInstance = new Player playerElement, preloadElement, localStorage, timeouter, playbackType
  songQueue = new SongQueue localStorage
  preloader = new Preloader songQueue, playbackType, PRELOAD_COUNT
  songQueue.on "queueChange", preloader.updatePreload

  PlayerView playerContainer, playerInstance, songQueue

  if localStorage.currentSong
    currentSong = jsonToSong localStorage.currentSong
    $("#title").text songTitle(currentSong)
    $("#album").text songAlbum(currentSong)
    $("#artist").text songArtist(currentSong)

  HotkeysView playerInstance, songQueue, $("#play-control"), $("#next"), $("#toggle-queue"), $("#search")

  router = new PlayerRouter()

  viewport = new Viewport document

  queueTable = $("#queue")
  playlist = $("#playlist")
  QueueView $("#toggle-queue"), queueTable, songQueue, playerInstance, playlist, viewport

  # Unfortunately DataTables does not support relative widths. So we need
  # to calculate column widths here.
  documentWidth = $(document).width()
  columnWidth = documentWidth / 3 - 20
  $("<style type='text/css'>.album, .artist, .title { max-width: #{columnWidth}; }</style>").appendTo("head");

  $("#initial-status").show()

  search = new Search SEARCH_WORKER, localStorage

  dataParser = (data, callback) ->
    search.initialize data
    start = (new Date()).getTime()
    directoriesDisplay = [""]
    for directory in data.directories[1...data.directories.length]
      [parentStr, name, normalizedName] = directory.split "/"
      if not normalizedName
        normalizedName = name
      directoriesDisplay.push [parentStr, name].join "/"

    progressCallback = ->
    fileId = 0
    if data.files.length > MINIMUM_PROGRESS_FILES
      progressElement = $("#parse-progress")
      $(progressElement).parent().show()
      progressCallback = ->
        progressElement.val (100 * fileId / data.files.length).toFixed(0)
    filesDisplay = []

    fields = {}
    for fieldKey, index in data.fields
      fields[fieldKey] = index

    for fileinfo, index in data.files
      fileId++
      if fileId % FILE_PROGRESS_UPDATE_INTERVAL == 0
        progressCallback()

      filesDisplay.push createSong fields, index, directoriesDisplay, fileinfo

    progressCallback()
    createPlayerElements filesDisplay

  createPlayerElements = (filesDisplay) ->
    songQueue.updateAll filesDisplay

    $("#initial-status").append $("<div>Creating playlist...</div>")

    PlaylistView playlist, filesDisplay, playerInstance, songQueue, router, search, viewport

    $("#initial-status").remove()

    search.on "initialize", ->
      end = (new Date()).getTime()
      console.log "TOTAL #{end - START_LOAD}"
      Backbone.history.start()

  $.ajax
    url: "files"
    dataType: 'json'
    xhr: ->
      xhr = new window.XMLHttpRequest()
      progressHandler = (event) ->
        if event.lengthComputable
          percentComplete = 100 * event.loaded / event.total
          $("#download-progress").val percentComplete.toFixed(0)
      xhr.addEventListener "progress", progressHandler, false
      return xhr
    success : dataParser
