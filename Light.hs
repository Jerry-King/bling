
-- | The functions dealing with colours, radiance and light sources
module Light (
   Spectrum, black, white, isBlack,
   Light, Directional(..), InfiniteArea(..),
   sampleOneLight, sampleAllLights) where

import Control.Monad

import Geometry
import Math
import Random

-- | A Spectrum of colours.
type Spectrum = Vector -- RGB for now

-- | A "black" @Spectrum@ (no transmittance or emission) at all wavelengths
black :: Spectrum
black = (0, 0, 0)

-- | A "white" @Spectrum@ (full transmission at any wavelength).
white :: Spectrum
white = (1, 1, 1)

-- | Decides if a @Spectrum@ is black (within an epsilon value).
isBlack :: Spectrum -> Bool
isBlack (r, g, b) = r < epsilon && g < epsilon && b < epsilon

data LightSample = LightSample {
   de :: Spectrum, -- ^ differential irradiance
   wo :: Vector, -- ^ incident direction
   testRay :: Ray -- ^ for visibility test
   }

class Light a where
   sampleLight :: a -> Intersection -> Rand LightSample

-- | An infinite area light; that is a "sphere of light" surrounding the whole scene,
-- emitting a constant amount of light from all directions.
data InfiniteArea = InfiniteArea {
   infiniteAreaRadiance :: Spectrum -- ^ the radiance emitted by this light
   }

instance Light InfiniteArea where
   sampleLight ia (Intersection _ pos n) = do
      rndD <- randomOnSphere
      dir <- return (sameHemisphere rndD n)
      return (LightSample (infiniteAreaRadiance ia) dir (add pos (scalMul n epsilon), dir))
      
-- | A directional light is a light source where for every point illuminated,
-- the light arrives from the same direction. This like a point light at
-- infinite distance.
data Directional = Directional {
   directionalDir :: Normal, -- ^ the direction this light emits to
   directionalRadiance :: Spectrum -- ^ the spectrum emitted by this light
   }
   
instance Light Directional where
   sampleLight dl (Intersection _ pos n) = return (LightSample y lDir ray) where
      y = scalMul (directionalRadiance dl) (abs (dot n lDir))
      ray = (pos, neg lDir)
      lDir = directionalDir dl

evalLight :: (Light l, Intersectable w) => w -> Intersection -> l -> Rand Spectrum
evalLight shape int light = do
   sample <- sampleLight light int
   return (evalSample sample shape)
   
evalSample :: (Intersectable i) => LightSample -> i -> Spectrum
evalSample sample shape = if (isBlack y)
                then black
                else if (not hidden)
                        then y
                        else black
   where
         y = de sample
         hidden = intersects ray shape
         ray = testRay sample

-- | samples all lights by sampling individual lights and summing up the results
sampleAllLights :: (Light l, Intersectable i) => i -> [l] -> Intersection -> Rand Spectrum
sampleAllLights _ [] _ = return black -- no light source means no light
sampleAllLights shape lights i  = (foldl (liftM2 add) (return black) spectri) -- sum up contributions
  where
    spectri = map (evalLight shape i) lights

-- | samples one randomly chosen light source
sampleOneLight :: (Light a, Intersectable i) => i -> [a] -> Intersection -> Rand Spectrum
sampleOneLight _ [] _ = return black -- no light sources -> no light
sampleOneLight shape (light:[]) i = evalLight shape i light
sampleOneLight shape lights i = do
  lightNum <-rndR (0, lightCount - 1)
  y <- return (evalLight shape i (lights !! lightNum))
  ((liftM2 scalMul) y (return (fromIntegral lightCount))) -- scale by probability choosing that light
  where
    lightCount = length lights
    