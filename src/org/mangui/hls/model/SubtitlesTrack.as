/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.model {
    /** Audio Track identifier **/
    public class SubtitlesTrack {
        public static const FROM_PLAYLIST : int = 1;
        public var title : String;
        public var language : String;
        public var id : int;
        public var source : int;
        public var isDefault : Boolean;
        public var isForced : Boolean;
        public var autoSelect : Boolean;
        public var level : Level;
        
        /**
         * Subtitles track model, based on alternative audio track model
         * @author    Neil Rackett
         */
        public function SubtitlesTrack(title:String, id:int, source:int=0, language:String='', isDefault:Boolean=false, isForced:Boolean=false, autoSelect:Boolean=false) {
            this.title = title;
            this.language = language;
            this.source = source;
            this.id = id;
            this.isDefault = isDefault;
            this.isForced = isForced;
            this.autoSelect = autoSelect;
        }

        public function toString() : String {
            return "SubtitlesTrack ID: " + id + " Title: " + title + " Source: " + source + " Default: " + isDefault + " Forced: " + isForced + " Auto Select: " + autoSelect;
        }
    }
}