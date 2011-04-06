{-# LANGUAGE ExistentialQuantification #-}

module Graphics.Bling.Primitive (

   -- * Ray - Primitive intersections

   Intersection(..), intLe, intBsdf,

   -- * Primitives

   Primitive(..), Geometry, mkGeom, mkMesh, nearest, AnyPrim(..)
   
   ) where

import Graphics.Bling.AABB
import Graphics.Bling.Light as L
import Graphics.Bling.Material
import Graphics.Bling.Math
import qualified Graphics.Bling.Shape as S
import Graphics.Bling.Spectrum
import Graphics.Bling.Transform
import Graphics.Bling.Transport

import Data.Maybe(fromJust, isJust, isNothing)

class Primitive a where
   intersect :: a -> Ray -> Maybe Intersection
   intersects :: a -> Ray -> Bool
   worldBounds :: a -> AABB
   flatten :: a -> [AnyPrim]
   
   light :: a -> Maybe Light
   
   light _ = Nothing
   
   -- | returns the geometry that should be used for shading computations
   shadingGeometry :: a -> Transform -> DifferentialGeometry -> DifferentialGeometry
   
   -- | the default implementation just returns the provided DG, so the
   --   geometry used for shading is the same as for reflection calculations
   shadingGeometry _ _ dg = dg

--
-- the existential primitive
--

data AnyPrim = forall a . Primitive a => MkAnyPrim a

instance Primitive AnyPrim where
   intersect (MkAnyPrim p) = intersect p
   intersects (MkAnyPrim p) = intersects p
   worldBounds (MkAnyPrim p) = worldBounds p
   flatten (MkAnyPrim p) = flatten p
   light (MkAnyPrim p) = light p

--
-- geometric primitives
--   

data Geometry = MkGeometry {
   o2w :: Transform, -- ^ the object-to-world transformation
   w2o :: Transform, -- ^ the world-to-object transformation
   _reverseOrientation :: Bool, -- ^ reverse the normal orientation?
   shape :: S.Shape,
   material :: Material,
   emission :: Maybe Spectrum
   } 

mkGeom
   :: Transform
   -> Bool
   -> Material
   -> Maybe Spectrum
   -> S.Shape
   -> Geometry
mkGeom t ro m e s = MkGeometry t (inverse t) ro s m e

mkMesh
   :: Material
   -> Maybe Spectrum
   -> Transform
   -> [[S.Vertex]]
   -> [Geometry]
mkMesh m e t vs = map (mkGeom t False m e) (S.triangulate vs)

instance Eq Geometry where

-- | transforms a @DifferentialGeometry@ to world space
transDg :: Transform -> DifferentialGeometry -> DifferentialGeometry
{-# INLINE transDg #-}
transDg t (DifferentialGeometry p n) =
   DifferentialGeometry (transPoint t p) (transNormal t n)

instance Primitive Geometry where
   flatten g = [MkAnyPrim g]
   
   worldBounds g = S.worldBounds (shape g) (o2w g)
   
   intersects g rw = S.intersects (shape g) (transRay (w2o g) rw)
   
   light g = maybe Nothing l (emission g) where
      l e = Just (mkAreaLight (shape g) e (o2w g))
   
   intersect g rw
      | isNothing mi = Nothing
      | otherwise = Just (Intersection t (transDg (o2w g) dg) p m)
      where
         m = material g
         p = MkAnyPrim g
         ro = transRay (w2o g) rw -- ray in object space
         mi = S.intersect (shape g) ro
         (t, dg) = fromJust mi
   
nearest :: (Primitive a) => Ray -> [a] -> Maybe Intersection
nearest (Ray ro rd tmin tmax) i = nearest' i tmax Nothing where
   nearest' [] _ mi = mi
   nearest' (x:xs) tmax' mi = nearest' xs newMax newNear where
      clamped = Ray ro rd tmin tmax'
      newNear = if isJust newNear' then newNear' else mi
      newNear' = intersect x clamped
      newMax = if isNothing newNear
                  then tmax'
                  else intDist $ fromJust newNear

--
-- Intersections
--

data Intersection = Intersection {
   intDist :: Float,
   intGeometry :: DifferentialGeometry,
   intPrimitive :: AnyPrim,
   intMaterial :: Material
   }

intBsdf :: Intersection -> Bsdf
intBsdf int = intMaterial int $ intGeometry int

-- | the light emitted at this intersection point
intLe :: Intersection -> Normal -> Spectrum
intLe (Intersection _ (DifferentialGeometry p n) prim _) wo
   | isJust l = L.lEmit (fromJust l) p n wo
   | otherwise = black
   where
         l = light prim
   