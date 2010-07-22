module WorldView
  ( sharedWorldView
  , requestSpecificWorldView
  , SharedTimelineView
  , WorldView
  , worldTemplate
  )
  where

import           Data.ByteString.Char8 (ByteString, pack, append)

import           Snap.Types
import           Text.JSONb
import qualified Data.Trie as Trie

import           ConcurrentUsers
import           Life
import           Life.JSON
import           Timeline

newtype SharedTimelineView = STV ByteString
newtype WorldView = WV { wvByteString::ByteString }

sharedWorldView :: World -> Tick -> SharedTimelineView
sharedWorldView world _ = STV (encode Compact $ worldToJson world)

requestSpecificWorldView :: SharedTimelineView -> Tick -> UserToken -> UserCount -> (WorldView, ByteString)
requestSpecificWorldView (STV worldJson) tick userToken count =
  let nextWorldUrl = "/world/next.json?tick=" `append` (pack $ show tick) `append` "&u=" `append` (tokenToString userToken)
      trieWithCount = Trie.singleton "userCount" (String (pack $ show count))
      trieWithUrl = add trieWithCount "nextUrl" (String nextWorldUrl)
      trieWithTick = add trieWithUrl "tick" (Number (toRational tick))
      extraInfo = encode Compact (Object trieWithTick)
  -- String together final JSON by hand so concurrent requests can share the worldJson bytestring
  in (WV $ "{" `append` "\"world\":" `append` worldJson `append` ", \"info\":" `append` extraInfo `append` "}", nextWorldUrl)

worldTemplate :: (WorldView, ByteString) -> Snap ()
worldTemplate (worldView, nextUrlBS) = do
  modifyResponse (setHeader "Location" nextUrlBS)
  writeBS (wvByteString worldView)
