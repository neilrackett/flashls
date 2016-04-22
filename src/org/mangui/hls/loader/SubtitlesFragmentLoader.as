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
    import flash.utils.clearTimeout;
    import flash.utils.setTimeout;
    
    import org.mangui.hls.HLS;
    import org.mangui.hls.HLSSettings;
    import org.mangui.hls.constant.HLSLoaderTypes;
    import org.mangui.hls.constant.HLSPlayStates;
    import org.mangui.hls.constant.HLSTypes;
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

        protected var _fragment:Fragment;
        protected var _remainingRetries:int;
        protected var _retryTimeout:uint;
		protected var _sequencer:SubtitlesSequencer;
		
		public function SubtitlesFragmentLoader(hls:HLS, streamBuffer:StreamBuffer) {

            _hls = hls;
			_streamBuffer = streamBuffer;
            
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
            _hls.addEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
            _hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			
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
            if (_hls.subtitlesTrack != -1) {
				_fragments = _fragments.concat(_hls.subtitlesTracks[_hls.subtitlesTrack].level.fragments);
	            loadNextFragment();
			}
        }
        
		/**
		 * Flashls flushes tags on seek, which wipes out VOD subtitles because they're
		 * all loaded at the start, so we need to reload them (live subtitles are
		 * per fragment, so they should take care of themselves)
		 */
        protected function seekStateHandler(event:HLSEvent):void {
			if (_hls.type == HLSTypes.VOD) {
				subtitlesLevelLoadedHandler(event);
			}
        }
        
        /**
         * Load the next subtitles fragment (if it hasn't been loaded already) 
         */
        protected function loadNextFragment():void {
            _remainingRetries = HLSSettings.fragmentLoadMaxRetry;
            _fragment = _fragments.shift();
            loadFragment();
        }
        
        /**
         * The load operation was separated from loadNextFragment() to enable retries
         */
        protected function loadFragment():void {
            clearTimeout(_retryTimeout);
			if (_fragment) {
            	_loader.load(new URLRequest(_fragment.url));
			}
        }
        
        /**
         * Parse the loaded WebVTT data
         */
        protected function loader_completeHandler(event:Event):void {
			appendSubtitles(WebVTTParser.parse(_loader.data, _fragment.level, _fragment.program_date));
            loadNextFragment();
        }
        
		/**
		 * Inject subtitles into the stream
		 */
		protected function appendSubtitles(subtitles:Vector.<Subtitle>):void {
			
			CONFIG::LOGGING {
				Log.debug("Appending "+subtitles.length+" subtitles from "+_fragment.url.split("/").pop()+":\n"+subtitles.join("\n"));
			}
			
			// Inject subtitles into the stream as onTextData events
			if (HLSSettings.subtitlesUseFlvTags) {
				
				var subtitle:Subtitle;
				var tags:Vector.<FLVTag> = new Vector.<FLVTag>();
				
				// Fill gaps in VOD subtitles (live streams include "" subtitles for gaps aleady)
				if (_hls.type == HLSTypes.VOD) {
					
					// Fill all the gaps
					for (var i:uint=0; i<subtitles.length-1; i++) {
						
						var nextSubtitle:Subtitle = subtitles[i+1];
						subtitle = subtitles[i];
						
						if (subtitle.endPTS < nextSubtitle.startPTS) {
							subtitles.splice(i+1, 0, new Subtitle(_fragment.level, '', subtitle.endPTS, nextSubtitle.startPTS, subtitle.endPosition, nextSubtitle.startPosition, subtitle.endTime, nextSubtitle.startTime));
						}
					}
					
					// ... and add a blank one at the end
					subtitles.push(new Subtitle(_fragment.level, '', subtitle.endPTS, subtitle.endPTS, subtitle.endPosition, subtitle.endPosition, subtitle.endTime, subtitle.endTime));
				}
				
				for each (subtitle in subtitles) {
					tags.push(subtitle.toTag());
				}
				
				_streamBuffer.appendTags(
					HLSLoaderTypes.FRAGMENT_SUBTITLES, 
					_fragment.level,
					_fragment.seqnum, 
					tags,
					_fragment.data.pts_min, 
					_fragment.data.pts_max, 
					_fragment.continuity, 
					_fragment.start_time
				);
				
				// TODO Should we be caching tags for VOD streams?
				
				// ... or sync them using MEDIA_TIME events?
			} else {
				// Sequencer
				_sequencer.appendSubtitles(subtitles, _fragment.seqnum);
			}
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
