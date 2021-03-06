/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.utils.clearTimeout;
    import flash.utils.getTimer;
    import flash.utils.setTimeout;
    
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.constant.HLSSeekStates;
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.event.HLSError;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSLoadMetrics;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.Level;
    import org.mangui.hls.model.SubtitlesTrack;
    import org.mangui.hls.playlist.Manifest;
    import org.mangui.hls.playlist.SubtitlesPlaylistTrack;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
        
    /**
     * Subtitles level loader, based on the alternative audio level loader
     * @author    Neil Rackett
     */
    public class SubtitlesLevelLoader {
        /** Reference to the hls framework controller. **/
        private var _hls : HLS;
        /** Reference to the hls level loader. **/
        private var _levelLoader : LevelLoader;
        /** Link to the M3U8 file. **/
        private var _url : String;
        /** Timeout ID for reloading live playlists. **/
        private var _timeoutID : uint;
        /** last reload manifest time **/
        private var _reloadPlaylistTimer : uint;
        /** current subtitles level **/
        private var _currentTrack : int;
        /** reference to manifest being loaded **/
        private var _manifestLoading : Manifest;
        /** is this loader closed **/
        private var _closed : Boolean = false;
        /* playlist retry timeout */
        private var _retryTimeout : Number;
        private var _retryCount : int;
		
        /** Setup the loader. **/
        public function SubtitlesLevelLoader(hls : HLS, levelLoader : LevelLoader) {
            _hls = hls;
            _hls.addEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);
            _hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, _subtitlesTrackSwitchHandler);
            _hls.addEventListener(HLSEvent.SEEK_STATE, _seekStateHandler);
			_hls.addEventListener(Event.CLOSE, closeHandler);
			
			_levelLoader = levelLoader;
		}
		
		protected function closeHandler(event:Event):void
		{
			// TODO Auto-generated method stub
			
		}
		
        public function dispose() : void {
            _close();
            _hls.removeEventListener(HLSEvent.PLAYBACK_STATE, _stateHandler);
            _hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, _subtitlesTrackSwitchHandler);
			_hls.removeEventListener(Event.CLOSE, closeHandler);
        }
		
		protected function _seekStateHandler(event:HLSEvent):void {
			if (_hls.seekState == HLSSeekStates.SEEKED) {
				_subtitlesTrackSwitchHandler(event);
			}
		}
		
        /** Loading failed; return errors. **/
        private function _errorHandler(event : ErrorEvent) : void {
            var txt : String;
            var code : int;
            if (event is SecurityErrorEvent) {
                code = HLSError.MANIFEST_LOADING_CROSSDOMAIN_ERROR;
                txt = "Cannot load M3U8: crossdomain access denied:" + event.text;
            } else if (event is IOErrorEvent && (HLSSettings.manifestLoadMaxRetry == -1 || _retryCount < HLSSettings.manifestLoadMaxRetry)) {
                CONFIG::LOGGING {
                    Log.warn(this+" I/O Error while trying to load Playlist, retry in " + _retryTimeout + " ms");
                }
                _timeoutID = setTimeout(_loadSubtitlesLevelPlaylist, _retryTimeout);
                /* exponential increase of retry timeout, capped to manifestLoadMaxRetryTimeout */
                _retryTimeout = Math.min(HLSSettings.manifestLoadMaxRetryTimeout, 2 * _retryTimeout);
                _retryCount++;
                return;
            } else {
                code = HLSError.MANIFEST_LOADING_IO_ERROR;
                txt = "Cannot load M3U8: " + event.text;
            }
            var hlsError : HLSError = new HLSError(code, _url, txt);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.ERROR, hlsError));
        };
        
        /** parse a playlist **/
        private function _parseSubtitlesPlaylist(string : String, url : String, level : int, metrics : HLSLoadMetrics) : void {
            
			if (_currentTrack < 0) return;
			
            if (string != null && string.length != 0) {
                CONFIG::LOGGING {
                    Log.debug(this+" subtitles level " + level + " playlist:\n" + string);
                }
                
                // Extract WebVTT subtitles fragments from the manifest
                var frags : Vector.<Fragment> = Manifest.getFragments(string, url, level);
                var subtitlesTrack : SubtitlesTrack = _hls.subtitlesTracks[_currentTrack];
                var subtitlesLevel : Level = subtitlesTrack.level;
                
                if(subtitlesLevel == null) {
                    subtitlesLevel = subtitlesTrack.level = new Level();
                }
                				
                subtitlesLevel.updateFragments(frags);
                subtitlesLevel.targetduration = Manifest.getTargetDuration(string);
				
                // if stream requires progressive download for subtitles, use a timer to periodically reload playlist
				// This is the default for LIVE, but typically not needed for VOD (which normally lists all fragments 
				// in the subtitles level manifest), but the option's there if you need it
                if (_hls.type == HLSTypes.LIVE || HLSSettings.subtitlesUseProgressiveDownloadForVod) {
                    var timeout : int = Math.max(10000, _reloadPlaylistTimer + 1000*subtitlesLevel.averageduration - getTimer());
                    CONFIG::LOGGING {
                        Log.debug(this+" Subtitles Level Live Playlist parsing finished: reload in " + timeout + " ms");
                    }
                    _timeoutID = setTimeout(_loadSubtitlesLevelPlaylist, timeout);
                }
            }
            
            metrics.id  = subtitlesLevel.start_seqnum;
            metrics.id2 = subtitlesLevel.end_seqnum;
            
            _hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_LEVEL_LOADED, metrics, frags));
            _manifestLoading = null;
        };

        /** load/reload active M3U8 playlist **/
        private function _loadSubtitlesLevelPlaylist() : void {
            
            if (_closed || _hls.subtitlesTrack == -1) {
                return;
            }
            
            _reloadPlaylistTimer = getTimer();
            
            var subtitlesPlaylistTrack : SubtitlesPlaylistTrack = _levelLoader.subtitlesPlaylistTracks[_hls.subtitlesTracks[_currentTrack].id];
			
            _manifestLoading = new Manifest();
            _manifestLoading.loadPlaylist(_hls, subtitlesPlaylistTrack.url, _parseSubtitlesPlaylist, _errorHandler, _currentTrack, _hls.type, HLSSettings.flushLiveURLCache);
            _hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_LEVEL_LOADING, _currentTrack));
        };

        /** When subtitles track switch occurs, load subtitles level playlist **/
        private function _subtitlesTrackSwitchHandler(event : HLSEvent) : void {
            
            _currentTrack = _hls.subtitlesTrack;
            clearTimeout(_timeoutID);
            
            if (_currentTrack > -1 && _currentTrack < _hls.subtitlesTracks.length) {
                
                var subtitlesTrack:SubtitlesTrack = _hls.subtitlesTracks[_currentTrack];
                
                if (subtitlesTrack.source == SubtitlesTrack.FROM_PLAYLIST) {
                    
                    var subtitlesPlaylistTrack : SubtitlesPlaylistTrack = _levelLoader.subtitlesPlaylistTracks[subtitlesTrack.id];
                    
                    if (subtitlesPlaylistTrack.url) {
                        
                        CONFIG::LOGGING {
                            Log.debug(this+" switch to subtitles track " + _currentTrack + ", load Playlist");
                        }
                        
                        _retryTimeout = 1000;
                        _retryCount = 0;
                        _closed = false;
                        
                        if(_manifestLoading) {
                           _manifestLoading.close();
                           _manifestLoading = null;
                        }
                        
                        _loadSubtitlesLevelPlaylist();
                    }
                }
            }
            
        };

        private function _close() : void {
            CONFIG::LOGGING {
                Log.debug(this+" Cancelling any subtitles level load in progress");
            }
            _closed = true;
            clearTimeout(_timeoutID);
            try {
                if (_manifestLoading) {
                    _manifestLoading.close();
                }
            } catch(e : Error) {}
        }

        /** When the framework idles out, stop reloading manifest **/
        private function _stateHandler(event : HLSEvent) : void {
            if (event.state == HLSPlayStates.IDLE) {
                _close();
            }
        };
    }
}
