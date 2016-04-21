/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils {
	
	import flash.events.Event;
	import flash.utils.Dictionary;
	
	import org.mangui.hls.HLS;
	import org.mangui.hls.HLSSettings;
	import org.mangui.hls.constant.HLSPlayStates;
	import org.mangui.hls.constant.HLSTypes;
	import org.mangui.hls.event.HLSEvent;
	import org.mangui.hls.event.HLSMediatime;
	import org.mangui.hls.event.HLSPlayMetrics;
	import org.mangui.hls.model.Subtitle;

	/**
	 * MEDIA-TIME SUBTITLE SEQUENCER
	 *
	 * This class sequences the selected subtitles based using MEDIA_TIME 
	 * events from the current stream; it will eventually be replaced with 
	 * onTextData events inserted into the stream using FLVTag data.
	 * 
	 * An experimental FLVTag implementation can be enabled using: 
	 * HLSSettings.subtitlesUseFlvTags = true;
	 * 
     * @author    Neil Rackett
	 */
	public class SubtitlesSequencer {
		
		protected var _hls:HLS;
		
		protected var _currentSubtitle:Subtitle;
		protected var _emptySubtitle:Subtitle;
		protected var _playMetrics:HLSPlayMetrics;
		protected var _seqIndex:int;
		protected var _seqSubs:Dictionary;
		
		public function SubtitlesSequencer(hls:HLS) {
			
			_hls = hls;
			_hls.addEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.addEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			_hls.addEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			
			_seqSubs = new Dictionary(true);
			_seqIndex = 0;
			_emptySubtitle = new Subtitle(-1, -1, '');
		}
		
		public function appendSubtitles(subtitles:Vector.<Subtitle>, sequenceNumber:uint=0):void
		{
			if (_hls.type == HLSTypes.LIVE) {
				_seqSubs[sequenceNumber] = subtitles;
			} else {
				_seqSubs[sequenceNumber] = true;
				_seqSubs[0] = (_seqSubs[0] is Vector.<Subtitle> 
					? _seqSubs[0] 
					: new Vector.<Subtitle>).concat(subtitles);
			}
		}
		
		public function stop():void {
			if (_currentSubtitle) {
				_currentSubtitle = null;
				dispatchSubtitle(_emptySubtitle);
			}
		}
		
		public function dispose():void {
			
			_hls.removeEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.removeEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			_hls.removeEventListener(HLSEvent.PLAYBACK_STATE, playbackStateHandler);
			_hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			
			_playMetrics = null;
			_seqSubs = null;
		}
		
		/**
		 * The currently displayed subtitles
		 */
		public function get currentSubtitle():Subtitle {
			return _currentSubtitle;
		}
		
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
					if (subtitle.startTime > pts) {
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
		
		protected function dispatchSubtitle(subtitle:Subtitle):void {
			
			// Regular events
			if (_hls.hasEventListener(HLSEvent.SUBTITLES_CHANGE)) {
				_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, subtitle));
			}
			
			// Pseudo-tag onTextData events
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
			&& subtitle.startTime <= pts
				&& subtitle.endTime >= pts;
		}
		
		/**
		 * When the media seeks, we reset the index from which we look for the next subtitles
		 */
		protected function seekStateHandler(event:Event):void {
			_seqIndex = 0;
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
			
			_seqSubs = new Dictionary(true);
			_seqIndex = 0;
		}
		
	}
	
}