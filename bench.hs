import Criterion.Main


main :: IO ()
main
  = defaultMain
      [ bgroup "my-group"
          [ bench "my-bench" $ whnf succ (0 :: Int)
          ]
      ]
