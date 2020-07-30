module Network.Warp.Request where

import Prelude

import Data.Bifunctor (lmap)
import Data.Int as Int
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Newtype (wrap)
import Data.String as String
import Data.String.CaseInsensitive (CaseInsensitiveString)
import Data.Tuple (Tuple)
import Effect (Effect)
import Foreign (unsafeToForeign)
import Foreign.Object as Object
import Network.HTTP.Types (http09, http10, http11)
import Network.HTTP.Types as Method
import Network.Wai (Request(..), RequestBodyLength(..))
import Node.HTTP as HTTP
import Node.Net.Socket as Socket
import Unsafe.Coerce (unsafeCoerce)

toWaiRequest :: HTTP.Request -> Effect Request
toWaiRequest httpreq = do 
  remoteHost <- getRemoteHost
  pure $ Request 
    { url
    , method
    , httpVersion
    , headers
    , body
    , contentLength
    , host
    , referer
    , userAgent 
    , remoteHost
    , range
    , isSecure
    , reqHandle
    }
  where
    url         = HTTP.requestURL httpreq
    method      = Method.fromString $ HTTP.requestMethod httpreq
    reqHandle   = pure $ unsafeToForeign httpreq
    headers     = httpHeaders httpreq
    body        = Just $ HTTP.requestAsStream httpreq
    host        = Map.lookup (wrap "host") $ Map.fromFoldable $ httpHeaders httpreq 
    referer     = Map.lookup (wrap "referer") $ Map.fromFoldable $ httpHeaders httpreq
    range       = Map.lookup (wrap "range") $ Map.fromFoldable $ httpHeaders httpreq
    userAgent   = Map.lookup (wrap "user-agent") $ Map.fromFoldable $ httpHeaders httpreq
    isSecure    = false
    httpVersion = parseHttpVersion $ HTTP.httpVersion httpreq
        where 
            parseHttpVersion = case _ of 
                "0.9"     -> http09
                "1.1"     -> http11
                otherwise -> http10
    getRemoteHost = remoteHost' $ _.socket $ unsafeCoerce httpreq
        where 
            remoteHost' socket = do 
                let mkHost mhost mport = (\h p -> String.joinWith ":" [h, show p]) <$> mhost <*> mport 
                mkHost <$> Socket.remoteAddress socket  <*> Socket.remotePort socket 

    contentLength = parseContentLength $ Map.lookup (wrap "content-length") $ Map.fromFoldable $ httpHeaders httpreq
      where 
          parseContentLength = 
              maybe ChunkedBody (KnownLength <<< fromMaybe 0 <<< Int.fromString) 

httpHeaders :: HTTP.Request -> Array (Tuple CaseInsensitiveString String) 
httpHeaders = map (lmap wrap) <<< Object.toUnfoldable <<< HTTP.requestHeaders