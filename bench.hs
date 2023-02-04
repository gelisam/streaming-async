import Criterion.Main

import Streaming.Async


main :: IO ()
main
  = defaultMain
      [ bgroup "my-group"
          [ bench "my-bench" $ whnf foo 0
          ]
      ]
