/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
	
	import flash.events.Event;
	import flash.utils.Dictionary;
	
	import org.mangui.hls.HLS;
	import org.mangui.hls.HLSSettings;
	import org.mangui.hls.constant.HLSPlayStates;
	import org.mangui.hls.event.HLSEvent;
	import org.mangui.hls.event.HLSMediatime;
	import org.mangui.hls.model.Subtitle;
	import org.mangui.hls.stream.HLSNetStreamClient;
	
	/**
	 * MEDIA-TIME SUBTITLE SEQUENCER FOR VOD
	 *
	 * This class sequences subtitles for VOD streams using MEDIA_TIME 
	 * events; it will be replaced with onTextData events appended to the 
	 * stream using FLVTag data once all the bugs are fixed.
	 * 
	 * The existing FLVTag implementation can be enabled for VOD using: 
	 * HLSSettings.subtitlesUseFlvTagsForVod = true;
	 * 
     * @author    Neil Rackett
	 */
	public class SubtitlesSequencer {
		
		protected var _hls:HLS;
		
		protected var _currentIndex:uint;
		protected var _currentSubtitle:Subtitle;
		protected var _tracks:Dictionary;
		
		use namespace hls_internal;
		
		public function SubtitlesSequencer(hls:HLS) {
			
			_hls = hls;
			_hls.addEventListener(HLSEvent.MANIFEST_LOADING, manifestLoadingHandler);
			_hls.addEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.addEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
			_hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			
			_currentIndex = 0;
			_tracks = new Dictionary(true);
		}
		
		public function appendSubtitles(trackId:uint, subtitles:Vector.<Subtitle>):void {
			var track:Vector.<Subtitle> = (_tracks[trackId] || new Vector.<Subtitle>()).concat(subtitles);
			_tracks[trackId] = track.sort(comparePts);
		}
		
		public function stop():void {
			_currentIndex = 0;
			if (_currentSubtitle) {
				_currentSubtitle = null;
				dispatchSubtitle(emptySubtitle);
			}
		}
		
		public function dispose():void {
			
			_hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.removeEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
			_hls.removeEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			_hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls = null;
			
			_currentIndex = 0;
			_currentSubtitle = null;
			_tracks = null;
		}
		
		public function get emptySubtitle():Subtitle {
			return new Subtitle(_hls.subtitlesTrack, "", _hls.position*1000, _hls.position*1000);
		}
		
		/**
		 * The currently displayed subtitles
		 */
		public function get currentSubtitle():Subtitle {
			return _currentSubtitle;
		}
		
		/**
		 * Sort by PTS in ascending order
		 */
		protected function comparePts(a:Subtitle, b:Subtitle):int {
			if (a.startPTS < b.startPTS) return -1;
			return 1;
		}
		
		/**
		 * It's a new stream, reset everything 
		 */
		protected function manifestLoadingHandler(event:HLSEvent):void {
			stop();
			_tracks = new Dictionary(true);
		}
		
		/**
		 * Match subtitles to the current playhead position and dispatch
		 * events as appropriate
		 */
		protected function mediaTimeHandler(event:HLSEvent):void {
			
			if (HLSSettings.subtitlesUseFlvTagForVod 
				|| _hls.subtitlesTrack == -1) {
				return;
			}
			
			var pts:Number = event.mediatime.pts;
			
			if (isSubtitleAt(_currentSubtitle, pts)) return;
			
			var mediaTime:HLSMediatime = event.mediatime;
			var track:Vector.<Subtitle> = _tracks[_hls.subtitlesTrack];
			var matchingSubtitle:Subtitle = emptySubtitle;
			
			if (track) {
				
				var i:uint;
				var length:uint = track.length;
				
				for (i=_currentIndex; i<length; ++i) {
					var subtitle:Subtitle = track[i];
					// There's no point searching more that we need to!
					if (subtitle.startPTS > pts) {
						break;
					}
					if (isSubtitleAt(subtitle, pts)) {
						matchingSubtitle = subtitle;
						break;
					}
				}
				
				_currentIndex = i;
			}
			
			if (!matchingSubtitle.equals(_currentSubtitle)) {
				_currentSubtitle = matchingSubtitle;
				dispatchSubtitle(matchingSubtitle);
			}
		}
		
		private function isSubtitleAt(subtitle:Subtitle, pts:Number):Boolean
		{
			return subtitle
				&& subtitle.startPTS <= pts
				&& subtitle.endPTS >= pts;
		}
		
		protected function dispatchSubtitle(subtitle:Subtitle):void {
			var client:HLSNetStreamClient = _hls.stream.hls_internal::client;
			client.onTextData(subtitle.toJSON());
		}
		
		/**
		 * When the media seeks, we reset the index from which we look for the next subtitles
		 */
		protected function seekStateHandler(event:Event):void {
			_currentIndex = 0;
		}
		
		protected function playbackStateHandler(event:HLSEvent):void {
			if (event.state == HLSPlayStates.IDLE) {
				stop();
			}
		}
		
		/**
		 * Handle switching subtitles track
		 */
		protected function subtitlesTrackSwitchHandler(event:HLSEvent):void {
			stop();
		}
		
	}
	
}