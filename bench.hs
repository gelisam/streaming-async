-- Confirm that splitting the work among multiple threads is faster than
-- doing it all in one thread.
{-# LANGUAGE BangPatterns #-}

import Control.Concurrent (getNumCapabilities)
import Control.Exception (evaluate)
import Control.Monad (replicateM)
import Criterion.Main
import Streaming (Stream, Of)
import qualified Control.Concurrent.Async as Async
import qualified Streaming.Prelude as Streaming

import Streaming.Async


-- | A CPU-bound computation which wastes the requested amount of CPU and then
-- returns some value.
{-# NOINLINE wasteCpu #-}
wasteCpu :: Int -> IO Int
wasteCpu effort = do
  evaluate $ go (effort * 1000000) 0
  where
    go :: Int -> Int -> Int
    go 0 !acc = acc
    go n !acc = go (n - 1) (acc + 1)

-- | A CPU-bound stream of the given length, wasting the requested amount of CPU
-- for each element.
cpuStream :: Int -> Int -> Stream (Of Int) IO ()
cpuStream n effort = Streaming.replicateM n (wasteCpu effort)

-- | Create and run a single stream of length n, without forking any threads.
runSingleThreadedStream :: Int -> IO ()
runSingleThreadedStream n = do
  let stream = cpuStream n 1
  Streaming.mapM_ evaluate stream

-- | Run n computations in parallel, without using any streams.
runMapConcurrently :: Int -> IO ()
runMapConcurrently n = do
  Async.mapConcurrently_ wasteCpu (replicate n 1)

-- | Fork k streams of length n and wait for them to complete.
forkStreams :: Int -> Int -> IO ()
forkStreams k n = do
  asyncStreams <- replicateM k $ do
    detachStream $ cpuStream n 1
  let combinedStream = mconcat asyncStreams
  Streaming.mapM_ evaluate $ attachStream combinedStream

-- Running on 16 cores:
--
--     evaluate stream:  ********
--     map-concurrently: **
--     1 thread:         ********
--     2 threads:        ****
--     4 threads:        **
--     8 threads:        **
--     16 threads:       ****************************************************
--
-- When the work items are too small, the overhead of STM conflicts dominates.
main :: IO ()
main = do
  n <- getNumCapabilities
  print $ "Running on " ++ show n ++ " cores"

  defaultMain
    [ bgroup "combining-streams"
        [ bench "evaluate stream" $ whnfIO $ runSingleThreadedStream 1280
        , bench "map-concurrently" $ whnfIO $ runMapConcurrently 1280
        , bench "1 thread" $ whnfIO $ forkStreams 1 1280
        , bench "2 threads" $ whnfIO $ forkStreams 2 640
        , bench "4 threads" $ whnfIO $ forkStreams 4 320
        , bench "8 threads" $ whnfIO $ forkStreams 8 160
        , bench "16 threads" $ whnfIO $ forkStreams 16 80
        ]
    ]
