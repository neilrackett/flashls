package org.mangui.hls.model
{
    import org.mangui.hls.utils.StringUtil;

    /**
     * Subtitle model for Flashls
     * @author    Neil Rackett
     */
    public class Subtitle
    {
		/**
		 * Convert an object (e.g. data from an onTextData event) into a 
		 * Subtitle class instance
		 */
		public static function toSubtitle(data:Object):Subtitle
		{
			return new Subtitle(data.startPosition, data.endPosition, data.htmlText || data.text);
		}
		
		
        private var _startPosition:Number;
        private var _endPosition:Number;
        private var _startPTS:Number;
        private var _endPTS:Number;
        private var _htmlText:String;
        
		/**
		 * Create a new Subtitle object
		 * 
		 * @param	startPosition	Relative start position from WebVTT
		 * @param	endPosition		Relative start position from WebVTT
		 * @param	htmlText		Subtitle text, including any HTML styling
		 * @param	pts				The program timestamp (fragment #EXT-X-PROGRAM-DATE-TIME directive)
		 */
        public function Subtitle(startPosition:Number, endPosition:Number, htmlText:String, pts:Number=0) 
        {
            _startPosition = startPosition;
            _endPosition = endPosition;
			
            _startPTS = pts + startPosition*1000;
            _endPTS = pts + endPosition*1000;
			
            _htmlText = htmlText || '';
        }
        
        public function get startPosition():Number { return _startPosition; }
        public function get endPosition():Number { return _endPosition; }
        public function get startPTS():Number { return _startPTS; }
        public function get endPTS():Number { return _endPTS; }
        public function get duration():Number { return _endPosition-_startPosition; }
        
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
                startPosition: startPosition,
                endPosition: endPosition,
                startPTS: startPTS,
                endPTS: endPTS,
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
				&& startPosition == subtitle.startPosition
				&& endPosition == subtitle.endPosition
				&& htmlText == subtitle.htmlText
				;
		}
        
        public function toString():String
        {
            return '[Subtitles startPosition='+startPosition+' endPosition='+endPosition+' htmlText="'+htmlText+'"]';
        }
	}
}