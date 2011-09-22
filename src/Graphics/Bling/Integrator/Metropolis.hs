
module Graphics.Bling.Integrator.Metropolis (

   Metropolis, mkMLT

   ) where

import Control.Monad
import Control.Monad.ST
import Data.STRef
import qualified Data.Vector.Unboxed.Mutable as V
import qualified Text.PrettyPrint as PP

import Graphics.Bling.Camera
import Graphics.Bling.DifferentialGeometry
import Graphics.Bling.Image
import Graphics.Bling.Integrator
import Graphics.Bling.Integrator.Path
import Graphics.Bling.Random as R
import Graphics.Bling.Reflection
import Graphics.Bling.Rendering
import Graphics.Bling.Sampling
import Graphics.Bling.Scene
import Graphics.Bling.Spectrum

data Metropolis = MLT
   { _integrator :: PathIntegrator
   , _ppp      :: Int -- ^ particles per pass
   }

maxDepth :: Int
maxDepth = 7

mkMLT :: Metropolis
mkMLT = MLT (mkPathIntegrator maxDepth) 10000

instance Printable Metropolis where
   prettyPrint (MLT integ ppp) = PP.vcat [
      PP.text "metropolis light transport",
      PP.text "integrator" PP.<+> prettyPrint integ,
      PP.int ppp PP.<+> PP.text "photons per pass" ]

instance Renderer Metropolis where
   render (MLT integ ppp) job report = pass img where
      scene = jobScene job
      img = mkJobImage job
      sSmp :: Flt -> ImageSample -> ImageSample
      sSmp f (ImageSample x y (w, s)) = ImageSample x y (w * f, s)
      pass i = do
            seed <- ioSeed

            img' <- stToIO $ do
               mimg <- thaw i
               
               runWithSeed seed $ do
                  x <- initialSample >>= newRandRef
                  x' <- readRandRef x >>= evalSample scene integ >>= newRandRef
                  
                  replicateM_ ppp $ do
                     y <- readRandRef x >>= mutate
                     y' <- evalSample scene integ y
                     
                     let iProp = evalI y'
                     iCurr <-  evalI `liftM` (readRandRef x')
                     let a = min 1 (iProp / iCurr)
                     

                     -- record samples
                     if iCurr > 0 && not (isInfinite (1 / iCurr))
                        then readRandRef x' >>= \s -> liftR (splatSample mimg $ sSmp (1-a) s)
                        else return ()
                     
                     if iProp > 0 && not (isInfinite (1 / iProp))
                        then liftR (splatSample mimg $ sSmp a y')
                        else return ()
   
                     R.rnd >>= \r -> if r < a
                        then do
                           writeRandRef x y
                           writeRandRef x' y'
                        else return ()
                     
               freeze mimg

            cont <- report $ (PassDone 1 img')
            if cont
               then pass img'
               else return ()

initialSample :: Rand s (Sample s)
initialSample = do
   v1d <- liftR $ V.new n1d
   v2d <- liftR $ V.new n2d
   
   forM_ [0..n1d-1] $ \i -> do
      x <- R.rnd
      liftR $ V.write v1d i x

   forM_ [0..n2d-1] $ \i -> do
      x <- R.rnd2D
      liftR $ V.write v2d i x

   ox <- R.rnd
   oy <- R.rnd
   luv <- R.rnd2D
   let cs = CameraSample (lerp ox 0 480) (lerp oy 0 480) luv
   
   return $ mkPrecompSample cs v1d v2d
   where
      n1d = maxDepth * 3
      n2d = maxDepth * 3

mutate :: Sample s -> Rand s (Sample s)
mutate (PrecomSample cs v1d v2d) = do
   R.rnd >>= \x -> if x < 0.25
      then initialSample
      else do

         forM_ [0..V.length v1d - 1] $ \i -> do
            v <- liftR $ V.read v1d i
            v' <- jitter v 0 1
            liftR $ V.write v1d i v'

         forM_ [0..V.length v2d - 1] $ \i -> do
            (u1, u2) <- liftR $ V.read v2d i
            u1' <- jitter u1 0 1
            u2' <- jitter u2 0 1
            liftR $ V.write v2d i (u1', u2')
         
         cs' <- mutateCamaraSample cs
         return $ PrecomSample cs' v1d v2d
mutate _ = error "mutate not precomputed sample"

mutateCamaraSample :: CameraSample -> Rand s CameraSample
mutateCamaraSample (CameraSample x y (lu, lv)) = do
   x' <- jitter x 0 480
   y' <- jitter y 0 480
   lu' <- jitter lu 0 1
   lv' <- jitter lv 0 1
   return $ CameraSample x' y' (lu', lv')

jitter :: Flt -> Flt -> Flt -> Rand s Flt
jitter v vmin vmax
   | vmin == vmax = return vmin
   | otherwise = do
      u <- R.rnd2D
      return $ jit u
   where
      jit (u1, u2) 
         | u2 < 0.5 = wrapAround vmin vmax  $ v + delta
         | otherwise = wrapAround vmin vmax  $ v - delta
         where
            delta = (vmax - vmin) * b * exp (logRat * u1)
      a = 1 / 1024
      b = 1 / 64
      logRat = -log (b / a)
      wrapAround x0 x1 x
         | x >= x1 = x0 + (x - x1)
         | x < x0 = x1 - (x0 - x)
         | otherwise = x

evalI :: ImageSample -> Flt
evalI (ImageSample _ _ (_, ss)) = sY ss

evalSample :: (SurfaceIntegrator i) => Scene -> i -> Sample s -> Rand s ImageSample
evalSample scn si smp = do
   smps <- liftR $ newSTRef []
   (flip randToSampled) smp $ do
      ray <- (fireRay (sceneCam scn))
      contrib si scn (\is -> modifySTRef smps (is :)) ray
   liftR $ head `liftM` readSTRef smps
   