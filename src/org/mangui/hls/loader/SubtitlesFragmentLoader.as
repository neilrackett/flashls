/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.loader
{
	import flash.events.ErrorEvent;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.SecurityErrorEvent;
	import flash.net.URLLoader;
	import flash.net.URLRequest;
	
	import org.mangui.hls.HLS;
	import org.mangui.hls.HLSSettings;
	import org.mangui.hls.constant.HLSTypes;
	import org.mangui.hls.event.HLSEvent;
	import org.mangui.hls.event.HLSMediatime;
	import org.mangui.hls.model.Fragment;
	import org.mangui.hls.model.Subtitles;
	import org.mangui.hls.utils.WebVTTParser;

	CONFIG::LOGGING 
	{
		import org.mangui.hls.utils.Log;
	}
	
	/**
	 * Subtitles fragment loader and sequencer
	 * @author	Neil Rackett
	 */
	public class SubtitlesFragmentLoader
	{
		protected var _hls:HLS;
		protected var _loader:URLLoader;
		protected var _fragments:Vector.<Fragment>;
		protected var _fragment:Fragment;
		protected var _seqSubs:Array;
		protected var _seqNum:Number;
		protected var _seqStartPosition:Number;
		protected var _currentSubtitles:Subtitles;
		protected var _seqSubsIndex:int;
		protected var _remainingRetries:int;
		
		public function SubtitlesFragmentLoader(hls:HLS)
		{
			_hls = hls;
			_hls.addEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls.addEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			_hls.addEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.addEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.addEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			
			_loader = new URLLoader();
			_loader.addEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.addEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.addEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			
			_seqSubs = [];
			_seqSubsIndex = 0;
		}
		
		public function dispose():void
		{
			stop();
			
			_hls.removeEventListener(HLSEvent.SUBTITLES_TRACK_SWITCH, subtitlesTrackSwitchHandler);
			_hls.removeEventListener(HLSEvent.SUBTITLES_LEVEL_LOADED, subtitlesLevelLoadedHandler);
			_hls.removeEventListener(HLSEvent.FRAGMENT_PLAYING, fragmentPlayingHandler);
			_hls.removeEventListener(HLSEvent.MEDIA_TIME, mediaTimeHandler);
			_hls.removeEventListener(HLSEvent.SEEK_STATE, seekStateHandler);
			_hls = null;
			
			_loader.removeEventListener(Event.COMPLETE, loader_completeHandler);
			_loader.removeEventListener(IOErrorEvent.IO_ERROR, loader_errorHandler);
			_loader.removeEventListener(SecurityErrorEvent.SECURITY_ERROR, loader_errorHandler);
			_loader = null;
			
			_seqSubs = null;
		}
		
		/**
		 * The currently displayed subtitles
		 */
		public function get currentSubtitles():Subtitles
		{
			return _currentSubtitles;
		}
		
		/**
		 * Stop any currently loading subtitles
		 */
		public function stop():void
		{
			try { _loader.close(); }
			catch (e:Error) {};
		}
		
		/**
		 * Handle the user switching subtitles track
		 */
		protected function subtitlesTrackSwitchHandler(event:HLSEvent):void
		{
			CONFIG::LOGGING 
			{
				Log.debug("Switching to subtitles track "+event.subtitlesTrack);
			}
			
			stop();
			
			if (_currentSubtitles)
			{
				_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, null));
			}
			
			_seqSubs = [];
			_seqSubsIndex = 0;			
		}
		
		/**
		 * Preload all of the subtitles listed in the loaded subtitles level definitions
		 */
		protected function subtitlesLevelLoadedHandler(event:HLSEvent):void
		{
			_fragments = _hls.subtitlesTracks[_hls.subtitlesTrack].level.fragments;
			loadNextFragment();
		}
		
		/**
		 * Sync subtitles with the current audio/video fragments
		 * 
		 * Live subtitles are assumed to contain times reletive to the current
		 * sequence, and VOD content relative to the entire video duration 
		 */
		protected function fragmentPlayingHandler(event:HLSEvent):void
		{
			if (_hls.type == HLSTypes.LIVE)
			{
				_seqNum = event.playMetrics.seqnum;
				_seqStartPosition = _hls.position;
				_seqSubsIndex = 0;
				
				return;
			}
			
			_seqNum = 0;
			_seqStartPosition = 0;
		}
		
		/**
		 * The current position relative to the start of the current sequence 
		 * (live) or to the entire video (VOD)
		 */
		protected function get seqPosition():Number
		{
			return _hls.position - _seqStartPosition;
		}
		
		/**
		 * Match subtitles to the current playhead position and dispatch
		 * events as appropriate
		 */
		protected function mediaTimeHandler(event:HLSEvent):void
		{
			var subs:Vector.<Subtitles> = _seqSubs[_seqNum];
			
			if (subs)
			{
				var mt:HLSMediatime = event.mediatime;
				var matchingSubtitles:Subtitles;
				var position:Number = seqPosition;
				var i:uint;
				var length:uint = subs.length;
				
				for (i=_seqSubsIndex; i<length; ++i)
				{
					var subtitles:Subtitles = subs[i];
					
					// There's no point searching more that we need to!
					if (subtitles.startPosition > position)
					{
						break;
					}
					
					if (subtitles.startPosition <= position && subtitles.endPosition >= position)
					{
						matchingSubtitles = subtitles;
						break;
					}
				}
				
				// To keep the search for the next subtitles as inexpensive as possible
				// for big VOD, we start the next search at the previous jump off point
				if (_hls.type == HLSTypes.VOD)
				{
					_seqSubsIndex = i;
				}
				
				if (matchingSubtitles != _currentSubtitles)
				{
					CONFIG::LOGGING 
					{
						Log.debug("Changing subtitles to: "+matchingSubtitles);
					}
					
					_currentSubtitles = matchingSubtitles;
					_hls.dispatchEvent(new HLSEvent(HLSEvent.SUBTITLES_CHANGE, matchingSubtitles));
				}
			}
		}
		
		/**
		 * When the media seeks, we reset the index from which we look for the next subtitles
		 */
		protected function seekStateHandler(event:Event):void
		{
			_seqSubsIndex = 0;
		}
		
		/**
		 * Load the next subtitles fragment (if it hasn't been loaded already) 
		 */
		protected function loadNextFragment():void
		{
			if (!_fragments || !_fragments.length) return;
			
			_remainingRetries = HLSSettings.fragmentLoadMaxRetry;
			_fragment = _fragments.shift();
			
			if (!_seqSubs[_fragment.seqnum])
			{
				loadFragment();
			}
			else
			{
				loadNextFragment();
			}
		}
		
		/**
		 * The load operation was separated from loadNextFragment() to enable retries
		 */
		protected function loadFragment():void
		{
			_loader.load(new URLRequest(_fragment.url));
		}
		
		/**
		 * Parse the loaded WebVTT subtitles
		 */
		protected function loader_completeHandler(event:Event):void
		{
			var parsed:Vector.<Subtitles> = WebVTTParser.parse(_loader.data);
			
			if (_hls.type == HLSTypes.LIVE)
			{
				_seqSubs[_fragment.seqnum] = parsed;
			}
			else
			{
				_seqSubs[_fragment.seqnum] = true;
				_seqSubs[0] = (_seqSubs[0] is Vector.<Subtitles> ? _seqSubs[0] : new Vector.<Subtitles>).concat(parsed);
			}
			
			CONFIG::LOGGING 
			{
				Log.debug("Loaded "+parsed.length+" subtitles from "+_fragment.url.split("/").pop()+":\n"+parsed.join("\n"));
			}
			
			loadNextFragment();
		}
		
		/**
		 * If the subtitles fail to load, give up and load the next subtitles fragment
		 */
		protected function loader_errorHandler(event:ErrorEvent):void
		{
			CONFIG::LOGGING 
			{
				Log.error("Error "+event.errorID+" while loading "+_fragment.url+": "+event.text);
				Log.error(_remainingRetries+" retries remaining");
			}
			
			if (_remainingRetries--)
			{
				loadFragment();
			}
			else
			{
				loadNextFragment();
			}
		}
		
	}

}
