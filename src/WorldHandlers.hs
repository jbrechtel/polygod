module WorldHandlers where

import           Control.Monad.Trans (liftIO)
import qualified Data.ByteString as Strict
import           Data.Char
import           Data.Time.Clock
import           Numeric

import qualified Text.JSONb as Json
import           Snap.Types

import           Life
import           Life.JSON
import           Timeline
import           Util
import           ConcurrentUsers
import           WorldView

updateWorldHandler :: Timeline a -> Snap ()
updateWorldHandler timeline = do
  body <- getRequestBody
  json <- processInput (Json.decode (strict body))
              "The post data was not valid JSON.  Please use JSON format to post updates to the world."

  newCells <- processInput (jsonToCells json)
               "The JSON you posted didn't include any properly structured cell data."

  liftIO $ interfere (updateCells newCells) timeline
  writeBS "Divine intervention successful.  Happy godding!\n"

generateNewUserToken :: UserSet -> Snap UserToken
generateNewUserToken userSet = do
  newUser <- liftIO (trackNewUser userSet)
  maybe (error500 "Failed to generate UUID" >> undefined) return newUser

worldHandler :: UserSet -> Timeline SharedTimelineView -> Snap ()
worldHandler userSet timeline = do
  user <- generateNewUserToken userSet
  (_, tick, sharedWorld) <- liftIO (now timeline)
  count <- liftIO (userCount userSet)
  worldTemplate $ requestSpecificWorldView sharedWorld tick user count

nextWorldHandler :: UserSet -> Timeline SharedTimelineView -> Snap ()
nextWorldHandler userSet timeline = do
    userTokenParam <- getParam "u"
    user <- maybe (generateNewUserToken userSet)
                  (\s -> processInput (tokenFromString s) "Malformed user token passed")
                  userTokenParam

    liftIO (trackUser user userSet)
    liftIO (reapStaleUsers (secondsToDiffTime 15) userSet)

    tickParam <- getParam "tick"

    maybe pass (\tickString ->
                    case readDec (map (chr . fromIntegral) (Strict.unpack tickString)) of
                      [(tick, [])] -> do (_, tick', sharedWorld) <- liftIO (worldAfter tick timeline)
                                         count <- liftIO (userCount userSet)
                                         worldTemplate $ requestSpecificWorldView sharedWorld tick' user count
                      _ -> pass)
          tickParam

badRequest :: Strict.ByteString -> Snap ()
badRequest = httpError 400 "Bad Request"

error500 :: Strict.ByteString -> Snap ()
error500 = httpError 500 "Internal Server Error"

httpError :: Int -> Strict.ByteString -> Strict.ByteString -> Snap ()
httpError code description message = do
  putResponse $
    setResponseStatus code description emptyResponse
  writeBS message
  writeBS "\n"
  r <- getResponse
  finishWith r

processInput :: PossibleBadInput m => m b -> Strict.ByteString -> Snap b
processInput input message = useGoodInput input return (badRequest message >> undefined)

class PossibleBadInput m where
  useGoodInput :: m a -> (a -> b) -> b -> b

instance PossibleBadInput Maybe where
  useGoodInput (Just a) f _ = f a
  useGoodInput _ _ b = b

instance PossibleBadInput (Either a) where
  useGoodInput (Right a) f _ = f a
  useGoodInput _ _ b = b
