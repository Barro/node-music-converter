Node music converter
====================

Node music converter is a HTML 5 based music player that converts
music collection to web playable format on song basis. It uses
Audacious playlist format for the playlist and ffmpeg for conversion
and supports any format that ffmpeg can convert.

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
