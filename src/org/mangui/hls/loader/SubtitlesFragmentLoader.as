/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader {
    
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.utils.Dictionary;
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;
    
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.Subtitle;
    import org.mangui.hls.stream.StreamBuffer;
    import org.mangui.hls.utils.SubtitlesSequencer;
    import org.mangui.hls.utils.WebVTTParser;
    import org.mangui.hls.utils.hls_internal;

    CONFIG::LOGGING {
        import org.mangui.hls.utils.Log;
    }
    
	use namespace hls_internal;
	
    /**
     * Subtitles fragment loader and sequencer
     * @author    Neil Rackett
     */
    public class SubtitlesFragmentLoader {
        
		protected var _hls:HLS;
		
		// Loader
        protected var _streamBuffer:StreamBuffer;
        protected var _loader:URLLoader;
        protected var _fragments:Vector.<Fragment> = new Vector.<Fragment>;
        protected var _fragmentHistory:Dictionary = new Dictionary(true);
        protected var _fragment:Fragment;
        protected var _remainingRetries:int;
        protected var _retryTimeout:uint;
		protected var _sequencer:SubtitlesSequencer;
		
        public function SubtitlesFragmentLoader(hls:HLS, streamBuffer:StreamBuffer) {

            _hls = hls;
			_streamBuffer = streamBuffer;
            
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
            _hls.addEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			
			_loader = new URLLoader();
			_loader.addEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.addEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			
			// Sequencer
			_sequencer = new SubtitlesSequencer(hls);
        }
		
        public function dispose():void {
            
            stop();
            
            _hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
            _hls.removeEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
            _hls = null;
            
            _loader.removeEventListener(Event.COMPLETE, loader_completeHandler);
            _loader.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
            _loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
            _loader = null;
            
			_fragmentHistory = null;
            _fragments = null;
            _fragment = null;
			
			// Sequencer
			_sequencer.dispose();
        }
        
        /**
         * Stop any currently loading subtitles
         */
        public function stop():void {
            
            try {
                _loader.close(); 
            } catch (e:Error) {};
            
            _fragments = new Vector.<Fragment>();
			_fragmentHistory = new Dictionary(true);
			
			// Sequencer
			_sequencer.stop();
        }
		
        /**
         * Handle the user switching subtitles track
         */
        protected function subtitlesTrackSwitchHandler(event:HLSEvent):void {
            
            CONFIG::LOGGING {
                Log.debug("Switching to subtitles track "+event.subtitlesTrack);
            }
            
            stop();
        }
        
        protected function playbackStateHandler(event:HLSEvent):void {
            if (event.state == HLSPlayStates.IDLE) {
                stop();
            }
        }
        
        /**
         * Preload all of the subtitles listed in the loaded subtitles level definitions
         */
        protected function subtitlesLevelLoadedHandler(event:HLSEvent):void {
            _fragments = _fragments.concat(_hls.subtitlesTracks[_hls.subtitlesTrack].level.fragments);
            loadNextFragment();
        }
        
        /**
         * Load the next subtitles fragment (if it hasn't been loaded already) 
         */
        protected function loadNextFragment():void {
            
            if (!_fragments || !_fragments.length) return;
            
            _remainingRetries = HLSSettings.fragmentLoadMaxRetry;
            _fragment = _fragments.shift();
            
            if (!_fragmentHistory[_fragment.seqnum]) {
                loadFragment();
            } else {
                loadNextFragment();
            }
        }
        
        /**
         * The load operation was separated from loadNextFragment() to enable retries
         */
        protected function loadFragment():void {
            clearTimeout(_retryTimeout);
            _loader.load(new URLRequest(_fragment.url));
        }
        
        /**
         * Parse the loaded WebVTT subtitles
         */
        protected function loader_completeHandler(event:Event):void {
            
			var pts:Number = _fragment.program_date;
            var parsed:Vector.<Subtitle> = WebVTTParser.parse(_loader.data, pts);
			
			CONFIG::LOGGING {
				Log.debug("Loaded "+parsed.length+" subtitles from "+_fragment.url.split("/").pop()+":\n"+parsed.join("\n"));
			}
			
			// Inject subtitles into the stream as onTextData events
			if (HLSSettings.subtitlesUseFlvTags) {
				
				var s:Subtitle;
				var tags:Vector.<FLVTag> = new Vector.<FLVTag>();
				
				for each (s in parsed) {
					tags.push(s.toTag());
				}
				
				// TODO Splice in blank subtitles to fill the gaps
				
				CONFIG::LOGGING {
					Log.debug(this+" >>> Appending "+tags.length+" subtitle tags ("+_fragment.data.pts_start_computed --> _fragment.data.pts_max+")");
				}
					
				_streamBuffer.appendTags(
					HLSLoaderTypes.FRAGMENT_SUBTITLES, 
					
					_fragment.level, // TODO Which level is this referring to? 
					_fragment.seqnum, 
					
					tags,
					
					_fragment.data.pts_start_computed, 
					_fragment.data.pts_max, 
					_fragment.continuity, 
					_fragment.start_time
				);
				
				_fragmentHistory[_fragment.seqnum] = true;
				
			// ... or sync them using MEDIA_TIME events
			} else {
				// Sequencer
				_sequencer.appendSubtitles(parsed, _fragment.seqnum);
			}
			
            loadNextFragment();
        }
        
        /**
         * If the subtitles fail to load, give up and load the next subtitles fragment
         */
        protected function loader_errorHandler(event:ErrorEvent):void {
            
            CONFIG::LOGGING {
                Log.error("Error "+event.errorID+" while loading "+_fragment.url+": "+event.text);
                Log.error(_remainingRetries+" retries remaining");
            }
            
            // We only wait 1s to retry because if we waited any longer the playhead will probably
            // have moved past the position where these subtitles were supposed to be used
            if (_remainingRetries--) {
                clearTimeout(_retryTimeout);
                _retryTimeout = setTimeout(loadFragment, 1000);
            } else {
                loadNextFragment();
            }
        }
		
    }

}
