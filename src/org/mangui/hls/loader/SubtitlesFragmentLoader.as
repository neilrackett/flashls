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
    import org.mangui.hls.constant.HLSTypes;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.event.HLSMediatime;
    import org.mangui.hls.event.HLSPlayMetrics;
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.model.Fragment;
    import org.mangui.hls.model.Subtitle;
    import org.mangui.hls.stream.StreamBuffer;
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
        protected var _fragments:Vector.<Fragment>;
        protected var _fragment:Fragment;
        protected var _remainingRetries:int;
        protected var _retryTimeout:uint;
		
		// Sequencer
        protected var _emptySubtitle:Subtitle;
		protected var _seqSubs:Dictionary;
		protected var _seqIndex:int;
		protected var _playMetrics:HLSPlayMetrics;
		protected var _currentSubtitle:Subtitle;

        public function SubtitlesFragmentLoader(hls:HLS, streamBuffer:StreamBuffer) {

            _hls = hls;
			_streamBuffer = streamBuffer;
			
			// Loader
            
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
            _hls.addEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			
			_fragments = new Vector.<Fragment>;
			
			_loader = new URLLoader();
			_loader.addEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.addEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			
			// Sequencer
            
			_hls.addEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
            _hls.addEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
            _hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
            _hls.addEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
            
            _seqSubs = new Dictionary(true);
            _seqIndex = 0;
            _emptySubtitle = new Subtitle(-1, -1, '');
        }
        
        public function dispose():void {
            
            stop();
            
            _hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
            _hls.removeEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
            _hls.removeEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
            _hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
            _hls.removeEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
            _hls.removeEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
            _hls = null;
            
            _loader.removeEventListener(Event.COMPLETE, loader_completeHandler);
            _loader.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
            _loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
            _loader = null;
            
			_playMetrics = null;
            _seqSubs = null;
            _fragments = null;
            _fragment = null;
        }
        
        /**
         * The currently displayed subtitles
         */
        public function get currentSubtitles():Subtitle {
            return _currentSubtitle;
        }
        
        /**
         * Stop any currently loading subtitles
         */
        public function stop():void {
            
            if (_currentSubtitle) {
                _currentSubtitle = null;
                dispatchSubtitle(_emptySubtitle);
            }
            
            try {
                _loader.close(); 
            } catch (e:Error) {};
            
            _fragments.splice(0, _fragments.length);
        }
        
        /**
         * Handle the user switching subtitles track
         */
        protected function subtitlesTrackSwitchHandler(event:HLSEvent):void {
            
            CONFIG::LOGGING {
                Log.debug("Switching to subtitles track "+event.subtitlesTrack);
            }
            
            stop();
            
            _seqSubs = new Dictionary(true);
            _seqIndex = 0;            
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
            
            if (!_seqSubs[_fragment.seqnum]) {
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
					tags.push(s.tag);
				}				
				
				/*
				_streamBuffer.appendTags(
					HLSLoaderTypes.FRAGMENT_ALTAUDIO,
					_fragCurrent.level,
					_fragCurrent.seqnum,
					fragData.tags, 
					fragData.tag_pts_min, 
					fragData.tag_pts_max + fragData.tag_duration, 
					_fragCurrent.continuity, 
					_fragCurrent.start_time + fragData.tag_pts_start_offset / 1000
				);
				
				_streamBuffer.appendTags(
					HLSLoaderTypes.FRAGMENT_MAIN,
					_fragCurrent.level,
					_fragCurrent.seqnum ,
					tags,
					_fragCurrent.data.pts_start_computed, 
					_fragCurrent.data.pts_start_computed + 1000*_fragCurrent.duration, 
					_fragCurrent.continuity, 
					_fragCurrent.start_time
				);
				
				_streamBuffer.appendTags(
					HLSLoaderTypes.FRAGMENT_MAIN,
					_fragCurrent.level,
					_fragCurrent.seqnum , 
					fragData.tags, 
					fragData.tag_pts_min, 
					fragData.tag_pts_max + fragData.tag_duration, 
					_fragCurrent.continuity, 
					_fragCurrent.start_time + fragData.tag_pts_start_offset / 1000
				);
				
				*/
				
				
				_streamBuffer.appendTags(
					HLSLoaderTypes.FRAGMENT_SUBTITLES, 
					
					_fragment.level, // TODO Should this be the current VIDEO level? 
					_fragment.seqnum, 
					
					tags,
					
					_fragment.data.pts_start_computed, 
					_fragment.data.pts_start_computed + 1000*_fragment.duration, 
					_fragment.continuity, 
					_fragment.start_time
				);
				
				_seqSubs[_fragment.seqnum] = true;
				
			// ... or sync them using MEDIA_TIME events
			} else {
	            if (_hls.type == HLSTypes.LIVE) {
	                _seqSubs[_fragment.seqnum] = parsed;
	            } else {
	                _seqSubs[_fragment.seqnum] = true;
	                _seqSubs[0] = (_seqSubs[0] is Vector.<Subtitle> ? _seqSubs[0] : new Vector.<Subtitle>).concat(parsed);
	            }
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
        
		
		/*
		 * MEDIA-TIME SEQUENCER
		 *
		 * The methods below are used by the media-time based subtitle 
		 * sequencer which will eventually be replaced by onTextData 
		 * events inserted into the stream using FLVTag data; an experimental
		 * FLVTag implementation can be enabled by setting subtitlesUseFlvTags
		 * to true in HLSSettings
		 */
		
		/**
		 * Sync subtitles with the current audio/video fragments
		 * 
		 * Live subtitles are assumed to contain times reletive to the current
		 * sequence, and VOD content relative to the entire video duration 
		 */
		protected function fragmentPlayingHandler(event:HLSEvent):void {
			
			if (HLSSettings.subtitlesUseFlvTags) return;
			
			_playMetrics = event.playMetrics;
			
			if (_hls.type == HLSTypes.LIVE) {
				
				// Keep track all the time to prevent delay in subtitles starting when selected
				_seqIndex = 0;
				
				// Only needed if subs are selected and being listened for
				if (_hls.subtitlesTrack != -1) {
					_currentSubtitle = _emptySubtitle;
					try {
						var targetDuration:Number = _hls.subtitlesTracks[_hls.subtitlesTrack].level.targetduration
						var dvrWindowDuration:Number = _hls.liveSlidingMain;
						var firstSeqNum:Number = _playMetrics.seqnum - (dvrWindowDuration/targetDuration);
						
						for (var seqNum:* in _seqSubs) {
							if (seqNum is Number && seqNum < firstSeqNum) {
								delete _seqSubs[seqNum];
							}
						}
					}
					catch(e:Error) {}
				}
				
				return;
			}
		}
		
		/**
		 * Match subtitles to the current playhead position and dispatch
		 * events as appropriate
		 */
		protected function mediaTimeHandler(event:HLSEvent):void {
			
			if (HLSSettings.subtitlesUseFlvTags 
				|| _hls.subtitlesTrack == -1 
				|| !_playMetrics) {
				return;
			}
			
			var isLive:Boolean = (_hls.type == HLSTypes.LIVE);
			var position:Number = isLive ? _hls.position%10 : _hls.position;
			var seqNum:uint = isLive ? _playMetrics.seqnum : 0;
			var pts:Number = _playMetrics.program_date + position*1000;
			
			if (isCurrentTime(_currentSubtitle, pts)) return;
			
			var mt:HLSMediatime = event.mediatime;
			var subs:Vector.<Subtitle> = _seqSubs[seqNum] || new Vector.<Subtitle>();
			var matchingSubtitle:Subtitle = _emptySubtitle;
			var i:uint;
			var length:uint = subs.length;
			
			if (length)
			{
				for (i=_seqIndex; i<length; ++i) {
					
					var subtitle:Subtitle = subs[i];
					
					// There's no point searching more that we need to!
					if (subtitle.startPTS > pts) {
						break;
					}
					
					if (isCurrentTime(subtitle, pts)) {
						matchingSubtitle = subtitle;
						break;
					}
				}
				
				// To keep the search for the next subtitles as inexpensive as possible
				// for big VOD, we start the next search at the previous jump off point
				if (_hls.type == HLSTypes.VOD) {
					_seqIndex = i;
				}
			}
			
			if (!matchingSubtitle.equals(_currentSubtitle)) {
				CONFIG::LOGGING {
					Log.debug("Changing subtitles to: "+matchingSubtitle);
				}
					_currentSubtitle = matchingSubtitle;
				dispatchSubtitle(matchingSubtitle);
			}
		}
		
		// TODO Replace this functionality using FLVTags
		protected function dispatchSubtitle(subtitle:Subtitle):void {
			
			if (_hls.hasEventListener(HLSEvent.SUBTITLES_CHANGE)) {
				_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, subtitle));
			}
			
			var client:Object = _hls.stream.client;
			if (client && client.hasOwnProperty("onTextData")) {
				var textData:Object = subtitle.toJSON();
				textData.trackid = _hls.subtitlesTrack;
				client.onTextData(textData);
			}
		}
		
		/**
		 * Are the specified subtitles the correct ones for the specified position?
		 */
		protected function isCurrentTime(subtitle:Subtitle, pts:Number):Boolean {
			return subtitle
			&& subtitle.startPTS <= pts
				&& subtitle.endPTS >= pts;
		}
		
		/**
		 * When the media seeks, we reset the index from which we look for the next subtitles
		 */
		protected function seekStateHandler(event:Event):void {
			_seqIndex = 0;
		}
		
    }

}
