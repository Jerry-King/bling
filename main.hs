--- RT - H

import Control.Monad
import System.Random
import Text.Printf
import Debug.Trace

import Camera
import Color
import Geometry
import Image
import Light
import Material
import Math
import Pathtracer
import Primitive
import Random
import Scene
import Whitted
   
---
--- sampling and reconstruction
---

-- creates the normalized device coordinates from xres and yres
ndc :: (Int, Int) -> (Int, Int) -> (Float, Float)
ndc (resX, resY) (px, py) = ((fromIntegral px / fromIntegral resX), (fromIntegral py / fromIntegral resY))

-- samples in x and y
stratify :: (Int, Int) -> (Int, Int) -> Rand [(Float, Float)]
stratify res@(resX, _) pixel = do
   
   return (map (pxAdd base) offsets) where
      base = ndc res pixel
      offsets = [(x / fpps , y / fpps) | 
         x <- (map fromIntegral [0::Int .. steps-1]),
         y <- (map fromIntegral [0::Int .. steps-1]) ]
      fpps = (fromIntegral steps) * (fromIntegral resX)
      pxAdd (x1, y1) (x2, y2) = (x1 + x2, y1 + y2)
      steps = 2

blub :: Sphere
blub = Sphere 0.6 (0,0,0)

blubLight :: Light
blubLight = AreaLight (1.0,1.0,1.0) (MkAnyBound blub)

defMat :: Matte
defMat = Matte (0.8, 0.8, 0.8)

red :: Matte
red = Matte (0.8, 0.3, 0.3)

green :: Matte
green = Matte (0.3, 0.8, 0.3)

blue :: Matte
blue = Matte (0.3, 0.3, 0.8)

myShape :: Group
myShape = Group [
   gP (Sphere (0.6) (1.3, 0, 0)) red Nothing,
   gP blub defMat (Just blubLight),
   gP (Sphere (0.6) (-1.3, 0, 0)) BluePaint Nothing,
   gP (Plane (2) (0, 0, -1)) defMat Nothing,
   gP (Plane (5) (1, 0, 0)) defMat Nothing,
   gP (Plane (5) (-1, 0, 0)) defMat Nothing,
   gP (Plane (0.6) (0, 1, 0)) Clay Nothing ]

myLights :: [Light]
myLights = [
    blubLight
--    Directional (2, 2, 2) (normalize (-2, 2, -2))
--      SoftBox (0.8, 0.8, 0.8)
    ]

resX :: Int
resX = 640

resY :: Int
resY = 480

myView :: View
myView = View (4, 2, -4) (-1,0,0) (0, 1, 0) 1.5 (fromIntegral resX / fromIntegral resY)

myCamera :: Camera
myCamera = pinHoleCamera myView

myScene :: Scene
myScene = Scene (MkAnyPrimitive myShape) myLights

onePass :: Image -> Scene -> Camera -> Integrator -> Rand Image
onePass img scene cam int = apply img pixels where
   pixels = imageSamples img
   sx = fromIntegral $ imageWidth img
   sy = fromIntegral $ imageHeight img
   apply :: Image -> [(Float, Float)] -> Rand Image
   apply i [] = return $! i
   apply i (p@(px, py):xs)
      | i `seq` p `seq` xs `seq` False = undefined
      | otherwise = do
      ws <- int scene (cam p)
      ns <- return $! ImageSample (px * sx) (py * sy) ws
      apply (ns `seq` i `seq` addSample i ns) xs

imageSamples :: Image -> [(Float, Float)]
imageSamples img = [ (fromIntegral x / fsx, fromIntegral y / fsy) | y <- [0..sy-1], x <- [0..sx-1]] where
   fsx = fromIntegral sx
   fsy = fromIntegral sy
   sx = imageWidth img
   sy = imageHeight img

   
render :: Int -> Image -> Scene -> Camera -> Integrator -> IO ()
render pass img sc cam int = do
   putStrLn "Rendering..."
   prng <- newStdGen
   img' <- return $! fromRand $ runRand prng (onePass img sc cam int) 
   putStrLn $ "Writing " ++ fname ++ "..."
   writeFile fname $ imageToPpm img'
   seq img' render (pass + 1) img' sc cam int
   where
         fname = "pass-" ++ (printf "%05d" pass) ++ ".ppm"

main :: IO ()
main = render 1 (makeImage resX resY) myScene myCamera pathTracer
         