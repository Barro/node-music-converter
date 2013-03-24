Node music converter
====================

Node music converter is a HTML 5 based music player that converts
music collection to web playable format on song basis. It uses
Audacious playlist format for the playlist and ffmpeg for conversion
and supports any format that ffmpeg can convert.

Design goals
------------

The design goals of this program are following:

* A HTML 5 music player (no Flash for music playback).
* Survive large (around 100k songs) playlists without hiccups.
* Provide immediate client side searches (no visible delay) for the
  playlist data.
* Support highly varied music formats with broken metadata
  information. Also support metadata for different writing systems
  that is possibly encoded with different character sets.
* Support my style of music playback patterns.

To achieve these it uses following techniques:

* Fully client side playlist operations to keep searches independent
  of the network delay. Fast dumb searches on normalized strings.
* [Unicode normalization](http://unicode.org/reports/tr15/) for search
  index and pattern creation in addition to other normalizations.
* [DataTables](http://www.datatables.net/) for data display.
* [Web workers](http://www.html5rocks.com/en/tutorials/workers/basics/)
  for search.
* [Audacious](http://audacious-media-player.org/) for playlist data
  creation.
* [FFmpeg](http://www.ffmpeg.org/) with [Node.js](http://nodejs.org/)
  to convert existing music on fly to something that the browser
  supports.

Installation
============

Go to Node music converter directory and type following command:

    make install

This will install all the dependency libraries that this application
has. This also compiles the frontend Javascript files that provide the
playback functionality.

Playlist creation
=================

You need to have either a file list that includes one file name per
line or file list that Audacious 3.3 creates. You can create the most
simple playlist by:

    find /music/directory -type f > /playlist-file.txt

This is fast but does not include any artist/title/album
information. More thorough and time taking method for playlist
creation is to use Audacious. Open Audacious and add the desired files
on to your playlist. Then you will have the playlist at files like:

    ~/.config/audacious/playlists/*.audpl

Running
=======

Now that you have created the playlists, you can go to Node music
converter directory and type following command:

    node_modules/.bin/coffee app.coffee ~/.config/audacious/playlists/*.audpl

License
=======

This program is licensed under [GNU Affero General Public License
version 3](http://www.gnu.org/licenses/agpl-3.0.html). See
[COPYING](COPYING) file for the exact license text.
