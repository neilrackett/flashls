/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
	
	import flash.events.Event;
	import flash.utils.Dictionary;
	
	import org.mangui.hls.HLS;
	import org.mangui.hls.constant.HLSPlayStates;
	import org.mangui.hls.constant.HLSSeekStates;
	import org.mangui.hls.constant.HLSTypes;
	import org.mangui.hls.event.HLSEvent;
	import org.mangui.hls.event.HLSMediatime;
	import org.mangui.hls.model.Subtitle;
	
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
		
		protected var _currentIndex:uint;
		protected var _currentSubtitle:Subtitle;
		protected var _hls:HLS;
		protected var _tracks:Dictionary;
		
		private var _enabled:Boolean = false;
		
		use namespace hls_internal;
		
		public function SubtitlesSequencer(hls:HLS) {
			_hls = hls;
			_currentIndex = 0;
			_tracks = new Dictionary(true);
		}
		
		/**
		 * Append subtitles for use with the specified track
		 */
		public function appendSubtitles(trackId:uint, subtitles:Vector.<Subtitle>):void {
			var track:Vector.<Subtitle> = (_tracks[trackId] || new Vector.<Subtitle>()).concat(subtitles);
			_tracks[trackId] = track.sort(comparePts);
			enabled = true;
		}
		
		/**
		 * Stop!
		 */
		public function stop():void {
			_currentIndex = 0;
			_currentSubtitle = null;
		}
		
		/**
		 * Destroy!
		 */
		public function dispose():void {
			
			enabled = false;
			
			_hls = null;
			_currentIndex = 0;
			_currentSubtitle = null;
			_tracks = null;
		}
		
		/**
		 * Create a time-specific empty subtitle
		 */
		public function get emptySubtitle():Subtitle {
			return new Subtitle(_hls.subtitlesTrack, "", _hls.pts, _hls.pts);
		}
		
		/**
		 * The currently displayed subtitles
		 */
		public function get currentSubtitle():Subtitle {
			return _currentSubtitle;
		}
		
		/**
		 * The sequencer is automatically disabled when a new track is loaded
		 * and enabled when one or more subtitles are appended
		 */
		protected function get enabled():Boolean {
			return _enabled;
		}
		protected function set enabled(value:Boolean):void {
			_enabled = value;
			
			if (value) {
				_hls.addEventListener(HLSEvent.MANIFEST_LOADING, manifestLoadingHandler);
				_hls.addEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
				_hls.addEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
				_hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
				_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			} else {
				_hls.removeEventListener(HLSEvent.MANIFEST_LOADING, manifestLoadingHandler);
				_hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
				_hls.removeEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
				_hls.removeEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
				_hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			}
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
			enabled = false;
			_tracks = new Dictionary(true);
		}
		
		/**
		 * Match subtitles to the current playhead position and dispatch
		 * events as appropriate
		 */
		protected function mediaTimeHandler(event:HLSEvent):void {
			
			if (_hls.subtitlesTrack == -1 
				|| !_tracks[_hls.subtitlesTrack]) {
				return;
			}
			
			var pts:Number = event.mediatime.pts;
			
			if (isSubtitleAt(_currentSubtitle, pts)) return;
			
			var mediaTime:HLSMediatime = event.mediatime;
			var track:Vector.<Subtitle> = _tracks[_hls.subtitlesTrack];
			var matchingSubtitle:Subtitle = _hls.type == HLSTypes.LIVE ? null : emptySubtitle;
			
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
			
			if (matchingSubtitle && !matchingSubtitle.equals(_currentSubtitle)) {
				_currentSubtitle = matchingSubtitle;
				dispatchTextData(matchingSubtitle);
			}
		}
		
		/**
		 * Is the specified subtitle the correct one for the specified PTS?
		 */
		private function isSubtitleAt(subtitle:Subtitle, pts:Number):Boolean
		{
			return subtitle
				&& subtitle.startPTS <= pts
				&& subtitle.endPTS >= pts;
		}
		
		/**
		 * Dispatch an onTextData event via the client object to emulate an FLVTag
		 */
		protected function dispatchTextData(subtitle:Subtitle):void {
			_hls.stream.dispatchClientEvent("onTextData", subtitle.toJSON());
		}
		
		/**
		 * When the media seeks, we reset the index from which we look for the next subtitles
		 */
		protected function seekStateHandler(event:Event):void {
			if (_hls.seekState == HLSSeekStates.SEEKING) {
				_currentIndex = 0;
			}
		}
		
		/**
		 * When the player is idle, stop
		 */
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