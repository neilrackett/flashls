/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
 package org.mangui.osmf.plugins.traits {
    import org.mangui.hls.HLS;
    import org.mangui.hls.event.HLSEvent;
    import org.mangui.hls.model.Level;
    import org.osmf.traits.MediaTraitBase;

    CONFIG::LOGGING {
    import org.mangui.hls.utils.Log;
    }

    public class HLSClosedCaptionsTrait extends MediaTraitBase {
        private var _hls : HLS;
        private var _hasClosedCapations : String;

        public function HLSClosedCaptionsTrait(hls : HLS, closed_captions : String = "unknown") {
            CONFIG::LOGGING {
            Log.debug(this+" HLSClosedCaptionsTrait()");
            }
            super(HLSMediaTraitType.CLOSED_CAPTIONS);

			_hasClosedCapations = closed_captions;
            _hls = hls;
            _hls.addEventListener(HLSEvent.LEVEL_SWITCH, _levelSwitchHandler);
        }

        override public function dispose() : void {
            CONFIG::LOGGING {
            Log.debug(this+" HLSClosedCaptionsTrait:dispose");
            }
            _hls.removeEventListener(HLSEvent.LEVEL_SWITCH, _levelSwitchHandler);
			_hls = null;
            super.dispose();
        }

        public function hasClosedCaptions() : String {
        	return _hasClosedCapations;
        }

        /** Update playback position/duration **/
        private function _levelSwitchHandler(event : HLSEvent) : void {
        	var cc : String;
			if (event.level != -1) {
				cc = Level(_hls.levels[event.level]).closed_captions;
			}
        	if (cc && cc === "NONE") {
        		// manifest told us to ignore any 608/708 binary
        		_hasClosedCapations = HLSClosedCaptionsState.NO;
        	} else {
    			_hasClosedCapations = HLSClosedCaptionsState.UNKNOWN;
    		}
    		// YES only happens for WebVTT
        }
    }
}