package org.mangui.hls.model
{
    import flash.net.ObjectEncoding;
    import flash.utils.ByteArray;
    
    import org.mangui.hls.flv.FLVTag;
    import org.mangui.hls.utils.StringUtil;
    import org.mangui.hls.utils.hls_internal;

	use namespace hls_internal;
	
    /**
     * Subtitle model for Flashls
     * @author    Neil Rackett
     */
    public class Subtitle
    {
		private var _tag:FLVTag; 
		
		/**
		 * Convert an object (e.g. data from an onTextData event) into a 
		 * Subtitle class instance
		 */
		public static function toSubtitle(data:Object):Subtitle
		{
			return new Subtitle(data.startTime, data.endTime, data.htmlText || data.text);
		}
		
		
        private var _startTime:Number;
        private var _endTime:Number;
        private var _htmlText:String;
        
		/**
		 * Create a new Subtitle object
		 * 
		 * @param	startTime		Start timestamp from WebVTT (fragment PTS + start position)
		 * @param	endTime			End timestamp from WebVTT (fragment PTS + end position)
		 * @param	htmlText		Subtitle text, including any HTML styling
		 */
        public function Subtitle(startTime:Number, endTime:Number, htmlText:String) 
        {
            _startTime = startTime;
            _endTime = endTime;
            _htmlText = htmlText || '';
        }
        
        public function get startTime():Number { return _startTime; }
        public function get endTime():Number { return _endTime; }
        public function get duration():Number { return _endTime-_startTime; }
		
        /**
         * The subtitle's text, including HTML tags (if applicable)
         */
        public function get htmlText():String { return _htmlText; }
        
        /**
         * The subtitles's text, with any HTML tags removed
         */
        public function get text():String { return StringUtil.removeHtmlTags(_htmlText); }
        
        /**
         * Convert to a plain object via the standard toJSON method
         */
        public function toJSON():Object
        {
            return {
				startTime: startTime,
				endTime: endTime,
                duration: duration,
                htmlText: htmlText,
                text: text
            }
        }
		
		/**
		 * Does this subtitle have the same content as the specified subtitle?
		 * @param	subtitle	The subtitle to compare
		 * @returns				Boolean true if the contents are the same
		 */
		public function equals(subtitle:Subtitle):Boolean
		{
			return subtitle is Subtitle
				&& startTime == subtitle.startTime
				&& endTime == subtitle.endTime
				&& htmlText == subtitle.htmlText
				;
		}
		
		hls_internal function toTag():FLVTag {
			
			if (!_tag) {
				_tag = new FLVTag(FLVTag.METADATA, startTime, startTime, false);
				
				var bytes:ByteArray = new ByteArray();
				
				bytes.objectEncoding = ObjectEncoding.AMF0;
				bytes.writeObject("onTextData");
				bytes.writeObject(toJSON());
				
				_tag.push(bytes, 0, bytes.length);
				_tag.build();
			}
			
			return _tag;
		}
		
		hls_internal function toTags():Vector.<FLVTag> {
			return Vector.<FLVTag>([toTag()]);
		}
		
        public function toString():String
        {
            return '[Subtitles startTime='+startTime+' endTime='+endTime+' htmlText="'+htmlText+'"]';
        }
	}
}