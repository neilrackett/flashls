/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls {

    import flash.display.Stage;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.net.NetConnection;
    import flash.net.URLLoader;
    import flash.net.URLStream;
    
    import org.mangui.hls.constant.HLSSeekStates;
    import org.mangui.hls.controller.AudioTrackController;
    import org.mangui.hls.controller.LevelController;
    import org.mangui.hls.controller.SubtitlesTrackController;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.loader.AltAudioLevelLoader;
    import org.mangui.hls.loader.LevelLoader;
    import org.mangui.hls.loader.SubtitlesLevelLoader;
    import org.mangui.hls.model.AudioTrack;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.model.SubtitlesTrack;
    import org.mangui.hls.playlist.AltAudioTrack;
    import org.mangui.hls.stream.HLSNetStream;
    import org.mangui.hls.stream.StreamBuffer;
    import org.mangui.hls.utils.hls_internal;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
	
	[Event(name="hlsEventManifestLoading", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventManifestParsed", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventManifestLoaded", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventLevelLoading", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventLevelLoadingAborted", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventLevelLoaded", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventLevelSwitch", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventLevelEndList", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventFragmentLoading", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventFragmentLoaded", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventFragmentLoadEmergencyAborted", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventFragmentPlaying", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventFragmentSkipped", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="audioTracksListChange", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="audioTrackSwitch", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventAudioLevelLoading", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventAudioLevelLoaded", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="subtitlesTracksListChange", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventSubtitlesTrackSwitch", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventSubtitlesLevelLoading", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventSubtitlesLevelLoaded", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventSubtitlesChange", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventTagsLoaded", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventLastFragmentLoaded", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventWarning", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventError", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventMediaTime", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsPlaybackState", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsSeekState", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventStreamTypeDidChange", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsEventPlayBackComplete", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsPlayListDurationUpdated", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsID3Updated", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsFPSDrop", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsFPSDropLevelCapping", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsFPSDropSmoothLevelSwitch", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsLiveLoadingStalled", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsStageSet", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="hlsReady", type="org.mangui.hls.event.HLSEvent")]
	[Event(name="fragmentMisalignment", type="org.mangui.hls.event.HLSEvent")]
	
    /** Class that manages the streaming process. **/
    public class HLS extends EventDispatcher {
        private var _levelLoader : LevelLoader;
        private var _altAudioLevelLoader : AltAudioLevelLoader;
        private var _audioTrackController : AudioTrackController;
        private var _subtitlesLevelLoader : SubtitlesLevelLoader;
        private var _subtitlesTrackController : SubtitlesTrackController;
        private var _levelController : LevelController;
        private var _streamBuffer : StreamBuffer;
        /** HLS NetStream **/
        private var _hlsNetStream : HLSNetStream;
        /** HLS URLStream/URLLoader **/
        private var _hlsURLStream : Class;
        private var _hlsURLLoader : Class;
        private var _client : Object = {};
        private var _stage : Stage;
        /* level handling */
        private var _level : int;
        /* overrided quality_manual_level level */
        private var _manual_level : int = -1;
        
		use namespace hls_internal;
		
        /** Create and connect all components. **/
        public function HLS() {
            _levelLoader = new LevelLoader(this);
            _altAudioLevelLoader = new AltAudioLevelLoader(this);
            _audioTrackController = new AudioTrackController(this);
            _levelController = new LevelController(this);
            _streamBuffer = new StreamBuffer(this, _audioTrackController, _levelController);
			_subtitlesLevelLoader = new SubtitlesLevelLoader(this, _levelLoader);
			_subtitlesTrackController = new SubtitlesTrackController(this, _streamBuffer, _levelLoader);
            _hlsURLStream = URLStream as Class;
            _hlsURLLoader = URLLoader as Class;
            // default loader
            var connection : NetConnection = new NetConnection();
            connection.connect(null);
            _hlsNetStream = new HLSNetStream(connection, this, _streamBuffer);
            this.addEventListener(HLSEvent.LEVEL_SWITCH, _levelSwitchHandler);
        };
		
		public function get fragsAppended():int {
			return _streamBuffer.fragsAppended;
		}
		
        /** Forward internal errors. **/
        override public function dispatchEvent(event : Event) : Boolean {
            if (event.type == HLSEvent.ERROR) {
                CONFIG::LOGGING {
                    Log.error((event as HLSEvent).error);
                }
                _hlsNetStream.close();
            }

            if (hasEventListener(event.type)) {
                return super.dispatchEvent(event);
            }

            return false;
        }

        private function _levelSwitchHandler(event : HLSEvent) : void {
            _level = event.level;
        };

        public function dispose() : void {
            this.removeEventListener(HLSEvent.LEVEL_SWITCH, _levelSwitchHandler);
            _levelLoader.dispose();
            _altAudioLevelLoader.dispose();
            _audioTrackController.dispose();
            _subtitlesLevelLoader.dispose();
            _subtitlesTrackController.dispose();
            _levelController.dispose();
            _hlsNetStream.$dispose();
            _streamBuffer.dispose();
            _levelLoader = null;
            _altAudioLevelLoader = null;
            _audioTrackController = null;
            _subtitlesLevelLoader = null;
            _subtitlesTrackController = null;
            _levelController = null;
            _hlsNetStream = null;
            _client = null;
            _stage = null;
            _hlsNetStream = null;
        }

        /** Return index of first quality level referenced in Manifest  **/
        public function get firstLevel() : int {
            return _levelController.firstLevel;
        };

        /** Return the quality level used when starting a fresh playback **/
        public function get startLevel() : int {
            return _levelController.startLevel;
        };

        /** Set the quality level used when starting a fresh playback */
        public function set startLevel(level : int) : void {
            _levelController.startLevel = level;
        };

        /** Return the quality level used after a seek operation **/
        public function get seekLevel() : int {
            return _levelController.seekLevel;
        };

        /** Return the quality level of the currently played fragment **/
        public function get currentLevel() : int {
            return _hlsNetStream.currentLevel;
        };

        /** Return the quality level of the next played fragment **/
        public function get nextLevel() : int {
            return _streamBuffer.nextLevel;
        };

        /** Return the quality level of last loaded fragment **/
        public function get loadLevel() : int {
            return _level;
        };

        /** instant quality level switch (-1 for automatic level selection) */
        public function set currentLevel(level : int) : void {
            _manual_level = level;
            // don't flush and seek if never seeked or if end of stream
            if(seekState != HLSSeekStates.IDLE) {
                _streamBuffer.flushBuffer();
                _hlsNetStream.seek(position);
            }
        };

        /** set quality level for next loaded fragment (-1 for automatic level selection) */
        public function set nextLevel(level : int) : void {
            _manual_level = level;
            _streamBuffer.nextLevel = level;
        };

        /** set quality level for next loaded fragment (-1 for automatic level selection) */
        public function set loadLevel(level : int) : void {
            _manual_level = level;
        };

        /** check if we are in automatic level selection mode */
        public function get autoLevel() : Boolean {
            return (_manual_level == -1);
        };

        /** return manual level */
        public function get manualLevel() : int {
            return _manual_level;
        };

        /** Return the capping/max level value that could be used by automatic level selection algorithm **/
        public function get autoLevelCapping() : int {
            return _levelController.autoLevelCapping;
        }

        /** set the capping/max level value that could be used by automatic level selection algorithm **/
        public function set autoLevelCapping(newLevel : int) : void {
            _levelController.autoLevelCapping = newLevel;
        }

        /** Return a Vector of quality level **/
        public function get levels() : Vector.<Level> {
            return _levelLoader.levels;
        };

        /** Return the current playback position. **/
        public function get position() : Number {
            return _streamBuffer.position;
        };

        /** Return the current PTS (experimental) **/
        public function get pts() : Number {
            return _streamBuffer.pts;
        };

        /** Return the current program date as a timestamp (experimental) **/
        public function get programDate() : Number {
            return _streamBuffer.programDate;
        };

        /** Return the live main playlist sliding in seconds since previous out of buffer seek(). **/
        public function get liveSlidingMain() : Number {
            return _streamBuffer.liveSlidingMain;
        }

        /** Return the live altaudio playlist sliding in seconds since previous out of buffer seek(). **/
        public function get liveSlidingAltAudio() : Number {
            return _streamBuffer.liveSlidingAltAudio;
        }

        /** Return the current playback state. **/
        public function get playbackState() : String {
            return _hlsNetStream.playbackState;
        };

        /** Return the current seek state. **/
        public function get seekState() : String {
            return _hlsNetStream.seekState;
        };

        /** Return the current watched time **/
        public function get watched() : Number {
            return _hlsNetStream.watched;
        };

        /** Return the total nb of dropped video frames since last call to hls.load() **/
        public function get droppedFrames() : Number {
            return _hlsNetStream.droppedFrames;
        };

        /** Return the type of stream (VOD/LIVE). **/
        public function get type() : String {
            return _levelLoader.type;
        };

        /** Load and parse a new HLS URL **/
        public function load(url : String) : void {
            _level = 0;
            _hlsNetStream.close();
            _levelLoader.load(url);
        };

        /** return HLS NetStream **/
        public function get stream() : HLSNetStream {
            return _hlsNetStream;
        }

        public function get client() : Object {
            return _client;
        }

        public function set client(value : Object) : void {
            _client = value;
        }

        /** get subtitles tracks list**/
        public function get subtitlesTracks() : Vector.<SubtitlesTrack> {
            return _subtitlesTrackController.subtitlesTracks;
        };

        /** get index of the selected subtitles track (index in subtitles track lists) **/
        public function get subtitlesTrack() : int {
            return _subtitlesTrackController.subtitlesTrack;
        };
        
		/** select a subtitles track, based on its index in subtitles track lists**/
        public function set subtitlesTrack(val : int) : void {
            _subtitlesTrackController.subtitlesTrack = val;
        }
        
        /** The ID of the default subtitles track */
        public function get defaultSubtitlesTrack():int {
            return _subtitlesTrackController.defaultSubtitlesTrack;
        }
        
        /** The ID of the forced subtitles track */
        public function get forcedSubtitlesTrack():int {
            return _subtitlesTrackController.forcedSubtitlesTrack;
        }
        
        /** Does the current subtitles playlist contain forced subtitles? */
        public function get hasForcedSubtitles():Boolean {
            return _subtitlesTrackController.hasForcedSubtitles;
        }
        
        /** get audio tracks list**/
        public function get audioTracks() : Vector.<AudioTrack> {
            return _audioTrackController.audioTracks;
        };

        /** get alternate audio tracks list from playlist **/
        public function get altAudioTracks() : Vector.<AltAudioTrack> {
            return _levelLoader.altAudioTracks;
        };

        /** get index of the selected audio track (index in audio track lists) **/
        public function get audioTrack() : int {
            return _audioTrackController.audioTrack;
        };

        /** select an audio track, based on its index in audio track lists**/
        public function set audioTrack(val : int) : void {
            _audioTrackController.audioTrack = val;
        }
        
		/** are we currently using an alternative audio track? */
		public function get isAltAudio():Boolean {
			return audioTracks 
				&& audioTracks.length 
				&& audioTrack >= 0 
				&& audioTracks[audioTrack].source == AudioTrack.FROM_PLAYLIST
		}
		
        /* set stage */
        public function set stage(stage : Stage) : void {
            _stage = stage;
            this.dispatchEvent(new HLSEvent(HLSEvent.STAGE_SET));
        }

        /* get stage */
        public function get stage() : Stage {
            return _stage;
        }

        /* set URL stream loader */
        public function set URLstream(urlstream : Class) : void {
            _hlsURLStream = urlstream;
        }

        /* retrieve URL stream loader */
        public function get URLstream() : Class {
            return _hlsURLStream;
        }

        /* set URL stream loader */
        public function set URLloader(urlloader : Class) : void {
            _hlsURLLoader = urlloader;
        }

        /* retrieve URL stream loader */
        public function get URLloader() : Class {
            return _hlsURLLoader;
        }
        /* start/restart playlist/fragment loading.
           this is only effective if MANIFEST_PARSED event has been triggered already */
        public function startLoad() : void {
            if(levels && levels.length) {
                this.dispatchEvent(new HLSEvent(HLSEvent.LEVEL_SWITCH, startLevel));
            }
        }
    }
}
