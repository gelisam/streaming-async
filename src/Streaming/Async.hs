-- | Run multiple computations from the "streaming" library concurrently and
-- combine the results.
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Streaming.Async
  ( AsyncStream
  , detachStream
  , attachStream
  ) where

import Control.Applicative
import Control.Concurrent.STM (STM)
import Control.Concurrent.STM.TQueue (newTQueue, readTQueue, writeTQueue)
import Control.Monad.IO.Class (liftIO)
import Streaming (Stream, Of)
import qualified Control.Concurrent.Async as Async
import qualified Control.Concurrent.STM as STM
import qualified Streaming.Prelude as Streaming


-- | 'Stream' is a description of the side-effects which would be required to
-- obtain the elements, while 'AsyncStream' is a handle on a thread which is
-- executing those side-effects and producing elements.
--
-- A 'Right' value is the next element of the 'Stream', while a 'Left' value is
-- the final result of the 'Stream'. Once a 'Left' value is returned, the same
-- value will be returned on every subsequent call to 'getNextElement'.
newtype AsyncStream a r = AsyncStream
  { unAsyncStream
      :: STM (Either r a)
  }

getElementIfAny
  :: AsyncStream a r -> STM a
getElementIfAny as = do
  unAsyncStream as >>= \case
    Right a -> do
      pure a
    Left _ -> do
      STM.retry

getResultIfAny :: AsyncStream a r -> STM r
getResultIfAny as = do
  unAsyncStream as >>= \case
    Right _ -> do
      STM.retry
    Left r -> do
      pure r

instance Functor (AsyncStream a) where
  fmap :: (r1 -> r2) -> AsyncStream a r1 -> AsyncStream a r2
  fmap f as = AsyncStream $ do
    unAsyncStream as >>= \case
      Right a -> do
        pure $ Right a
      Left r -> do
        pure $ Left (f r)

instance Applicative (AsyncStream a) where
  pure :: r -> AsyncStream a r
  pure r = AsyncStream $ do
    pure $ Left r

  (<*>) :: forall r1 r2. AsyncStream a (r1 -> r2) -> AsyncStream a r1 -> AsyncStream a r2
  asF <*> asR1
    = AsyncStream
       ( (Left <$> getBothResults)
     <|> (Right <$> getElementIfAny asF)
     <|> (Right <$> getElementIfAny asR1)
       )
    where
      getBothResults :: STM r2
      getBothResults = getResultIfAny asF <*> getResultIfAny asR1

instance Semigroup r => Semigroup (AsyncStream a r) where
  (<>) :: AsyncStream a r -> AsyncStream a r -> AsyncStream a r
  (<>) = liftA2 (<>)

instance Monoid r => Monoid (AsyncStream a r) where
  mempty :: AsyncStream a r
  mempty = pure mempty

-- | Run the 'Stream' in a separate thread.
detachStream :: Stream (Of a) IO r -> IO (AsyncStream a r)
detachStream stream = do
  queue <- STM.atomically newTQueue
  async <- Async.async $ do
    flip Streaming.mapM_ stream $ \a -> do
      STM.atomically $ writeTQueue queue a

  -- Read from the queue first, in case the thread both wrote the queue and
  -- exited.
  pure $ AsyncStream
      ( (Right <$> readTQueue queue)
    <|> (Left <$> Async.waitSTM async)
      )

-- | Wait for the 'AsyncStream' to emit all of its elements and then return the
-- final result.
attachStream :: AsyncStream a r -> Stream (Of a) IO r
attachStream asyncStream = do
  rOrA <- liftIO $ STM.atomically $ unAsyncStream asyncStream
  case rOrA of
    Right a -> do
      Streaming.yield a
      attachStream asyncStream
    Left r -> do
      pure r
