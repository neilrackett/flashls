package org.mangui.hls.model
{
	import org.mangui.hls.utils.StringUtil;

    /**
     * Subtitle model for Flashls
     * @author    Neil Rackett
     */
    public class Subtitle
    {
        private var _startPosition:Number;
        private var _endPosition:Number;
        private var _htmlText:String;
        
        public function Subtitle(startPosition:Number, endPosition:Number, htmlText:String) 
        {
            _startPosition = startPosition;
            _endPosition = endPosition;
            _htmlText = htmlText || '';
        }
        
        public function get startPosition():Number { return _startPosition; }
        public function get endPosition():Number { return _endPosition; }
        public function get duration():Number { return _endPosition-_startPosition; }
		
		/**
		 * The subtitle's text, including HTML tags (if applicable)
		 */
        public function get htmlText():String { return _htmlText; }
		
		/**
		 * The subtitles's text, with any HTML tags removed
		 */
        public function get text():String { return StringUtil.removeHtmlTags(_htmlText); }
        
        public function toString():String
        {
            return '[Subtitles startPosition='+startPosition+' endPosition='+endPosition+' htmlText="'+htmlText+'"]';
        }
    }
}