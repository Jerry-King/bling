
module Graphics.Bling.Integrator.BidirPath (
   BidirPath, mkBidirPathIntegrator
   ) where

import Data.BitSet
import qualified Data.Vector.Unboxed.Mutable as MV
import qualified Data.Vector.Unboxed as V
import Control.Monad (liftM, forM, forM_)
import Control.Monad.ST
import qualified Text.PrettyPrint as PP

import Graphics.Bling.DifferentialGeometry
import Graphics.Bling.Integrator
import Graphics.Bling.Primitive
import Graphics.Bling.Random
import Graphics.Bling.Reflection
import Graphics.Bling.Sampling
import Graphics.Bling.Scene
import Graphics.Bling.Spectrum

data BidirPath = BDP
   { _maxDepth    :: Int
   , _sampleDepth :: Int
   }
   
-- | a path vertex
data Vertex = Vert
   { _vbsdf    :: Bsdf
   , _vpoint   :: Point
   , _vwi      :: Vector
   , _vwo      :: Vector
   , _vint     :: Intersection
   , _vtype    :: BxdfType
   , _valpha   :: Spectrum
   }

type Path = [Vertex]

mkBidirPathIntegrator :: Int -> Int -> BidirPath
mkBidirPathIntegrator = BDP 

instance Printable BidirPath where
   prettyPrint (BDP _ _) = PP.text "Bi-Dir Path"


smps2D :: Int
smps2D = 3

smps1D :: Int
smps1D = 4

smp1doff :: Int -> Int
smp1doff d = smps1D * d + 1

smp2doff :: Int -> Int
smp2doff d = smps2D * d + 2

instance SurfaceIntegrator BidirPath where
   sampleCount1D (BDP _ sd) = smps1D * sd + 1
   sampleCount2D (BDP _ sd) = smps2D * sd + 2
   
   contrib (BDP md _) scene addContrib' r = do
      ul <- rnd' 0
      ulo <- rnd2D' 0
      uld <- rnd2D' 1
      
      lp <- lightPath scene md ul ulo uld
      ep <- eyePath scene r md
      
      -- precompute sum of specular bounces in eye or light path
      let nspecBouces = countSpec ep lp
      
      -- direct illumination, aka "one light" or S1 subpaths
      ld <- liftM sum $ forM (zip ep [1..]) $ \(v, i) -> do
         d <- estimateDirect scene v i
         return $ sScale d $ 1 / (fromIntegral i - (nspecBouces V.! i))

      let prevSpec = True : map (\v -> Specular `member` _vtype v) ep

      -- light sources directly visible, or by specular reflection
      let le = sum $ map (\v -> _valpha v * (intLe (_vint v) (_vwi v))) $ map fst $ filter snd $ zip ep prevSpec
      
      let ei = zip ep [0..]
      let li = zip lp [0..]

      let l = sum $ map (connect scene nspecBouces) $ pairs ei li
      mkContrib (1, l + ld + le) False >>= addContrib
      where
         addContrib = liftSampled . addContrib'

--------------------------------------------------------------------------------
-- Path Evaluation
--------------------------------------------------------------------------------

-- compute number of specular vertices for each path length
countSpec :: Path -> Path -> V.Vector Flt
countSpec ep lp = runST $ do
   x <- MV.replicate (length ep + length lp + 2) 0
   forM_ [0..length ep - 1] $ \i -> do
      forM_ [0..length lp - 1] $ \j -> do
         if Specular `member` (_vtype $ ep !! i) || Specular `member` (_vtype $ lp !! j)
            then do
               old <- MV.read x (i+j+2)
               MV.write x (i+j+2) (old + 1)
            else return ()
   V.freeze x

connect :: Scene -> V.Vector Flt -> ((Vertex, Int),  (Vertex, Int)) -> Spectrum
connect scene nspec
   ((Vert bsdfe pe wie _ _ te alphae, i),  -- eye vertex
    (Vert bsdfl pl wil _ _ tl alphal, j))   -- camera vertex
       | Specular `member` te = black
       | Specular `member` tl = black
       | isBlack fe || isBlack fl = black
       | scene `intersects` r = black
       | otherwise = sScale (alphae * fe * alphal * fl) (g * pathWt)
       where
          pathWt = 1 / (fromIntegral (i + j + 2) - nspec V.! (i+j+2))
          g = absDot ne w * absDot nl w / sqLen (pl - pe)
          w = normalize $ pl - pe
          nspece = fromIntegral $ bsdfSpecCompCount bsdfe
          fe = sScale (evalBsdf bsdfe wie w) (1 + nspece)
          nspecl = fromIntegral $ bsdfSpecCompCount bsdfl
          fl = sScale (evalBsdf bsdfl (-w) wil) (1 + nspecl)
          r = segmentRay pl pe
          ne = bsdfShadingNormal bsdfe
          nl = bsdfShadingNormal bsdfl
             
estimateDirect :: Scene -> Vertex -> Int -> Sampled s Spectrum
estimateDirect scene (Vert bsdf p wi _ _ _ alpha) depth = do
   lNumU <- rnd' $ 2 + smp1doff depth
   lDirU <- rnd2D' $ 1 + smp2doff depth
   lBsdfCompU <- rnd' $ 3 + smp1doff depth
   lBsdfDirU <- rnd2D' $ 2 + smp2doff depth
   let lHere = sampleOneLight scene p n wi bsdf $ RLS lNumU lDirU lBsdfCompU lBsdfDirU
   return $ lHere * alpha
   where
      n = bsdfShadingNormal bsdf

pairs :: [a] -> [a] -> [(a, a)]
pairs [] _ = []
pairs _ [] = []
pairs (x:xs) ys = zip (repeat x) ys ++ pairs xs ys

--------------------------------------------------------------------------------
-- Path Generation
--------------------------------------------------------------------------------

-- | generates the eye path
eyePath :: Scene -> Ray -> Int -> Sampled m Path
eyePath s r md = nextVertex s wi int white 0 md (\d -> 2 + smp1doff d) (\d -> 2 + smp2doff d) where
   wi = normalize $ (-(rayDir r))
   int = s `intersect` r

-- | generates the light path
lightPath :: Scene -> Int -> Flt -> Rand2D -> Rand2D -> Sampled m Path
lightPath s md ul ulo uld = do
   let (li, ray, nl, pdf) = sampleLightRay s ul ulo uld
   let wo = normalize $ rayDir ray
   let nl' = normalize nl
   nextVertex s (-wo) (s `intersect` ray) (sScale li (absDot nl' wo / pdf)) 0 md (\d -> 3 + smp1doff d) (\d -> 3 + smp2doff d)
   
nextVertex
   :: Scene
   -> Vector
   -> Maybe Intersection
   -> Spectrum -- ^ alpha
   -> Int -- ^ depth
   -> Int -- ^ maximum depth
   -> (Int -> Int) -- ^ 1d offsets
   -> (Int -> Int) -- ^ 2d offsets
   -> Sampled m Path
-- nothing hit, terminate path
nextVertex _ _ Nothing _ _ _ _ _ = return []
nextVertex sc wi (Just int) alpha depth md f1d f2d
   | depth == md = return []
   | otherwise = do
      ubc <- rnd' $ f1d depth -- bsdf component
      ubd <- rnd2D' $ f2d depth -- bsdf dir
      rr <- rnd' $ 1 + f1d depth -- russian roulette
      
      let (BsdfSample t spdf f wo) = sampleBsdf bsdf wi ubc ubd
      let int' = intersect sc $ Ray p wo epsilon infinity
      let wi' = -wo
      let vHere = Vert bsdf p wi wo int t alpha
      let pathScale = sScale f $ absDot wo (bsdfShadingNormal bsdf) / spdf
      let rrProb = min 1 $ sY pathScale
      let alpha' = sScale (pathScale * alpha) (1 / rrProb)
      let rest = if rr > rrProb
                  then return [] -- terminate
                  else nextVertex sc wi' int' alpha' (depth + 1) md f1d f2d
   
      if isBlack f || spdf == 0
         then return [vHere]
         else (liftM . (:)) vHere $! rest
   
      where
         dg = intGeometry int
         bsdf = intBsdf int
         p = dgP dg
