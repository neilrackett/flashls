/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */
package org.mangui.hls.utils
{
    import org.mangui.hls.model.Subtitle;

    /**
     * WebVTT subtitles parser
     * 
     * It supports standard WebVTT format text with or without align:* 
     * elements, which are currently ignored.
     * 
     * This class is loosely based Denivips's WebVTT parser, but has been 
     * massively simplified, re-worked and generally updated to more reliably 
     * capture subtitle text in as small amount of code as possible. 
     * 
     * @author    Neil Rackett
     */
    public class WebVTTParser
    {
        static private const CUE:RegExp = /^(?:(.*)(?:\n))?([\d:,.]+) --> ([\d:,.]+)((.|\n)*)/;
        static private const TIMESTAMP:RegExp = /^(?:(\d{2,}):)?(\d{2}):(\d{2})[,.](\d{3})$/;
        
        /**
         * Parse a string into a series of Subtitles objects and return
         * them in a Vector
		 * 
		 * Alignment data is currently removed.
         */
        static public function parse(data:String, pts:Number=0, keepEmpty:Boolean=true):Vector.<Subtitle>
        {
			data = StringUtil.toLF(data);
			
            var results:Vector.<Subtitle> = new Vector.<Subtitle>;
            var lines:Array = data.replace(/\balign:.*+/ig,'').split(/(?:(?:\n){2,})/);
            
            for each (var line:String in lines)
            {
                if (!CUE.test(line)) continue;
                
                var matches:Array = CUE.exec(line);
                var startPosition:Number = parseTime(matches[2]);
                var endPosition:Number = parseTime(matches[3]);
                var text:String = StringUtil.trim((matches[4] || '').replace(/(\|)/g, '\n'));
                
                if (keepEmpty || text)
                {
                    var subs:Subtitle = new Subtitle(startPosition, endPosition, text, pts);
                    
                    CONFIG::LOGGING 
                    {
                        Log.debug(subs);
                    }
                    
                    results.push(subs);
                }
            }
            
            return results;
        }
        
        /**
         * Converts a time string in the format 00:00:00.000 into seconds
         */
        static public function parseTime(time:String):Number
        {
            if (!TIMESTAMP.test(time)) return NaN;
            
            var a:Array = TIMESTAMP.exec(time);
            var seconds:Number = a[4]/1000;
            
            seconds += parseInt(a[3]);
            
            if (a[2]) seconds += a[2] * 60;
            if (a[1]) seconds += a[1] * 60 * 60;
            
            return Math.round(seconds*10)/10;
        }
        
    }
    
}
