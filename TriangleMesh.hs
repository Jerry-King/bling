
module TriangleMesh (Vertex(..), Triangle, triangulate) where

import Debug.Trace
import Geometry
import Math

data Vertex = Vertex {
   vertexPos :: Point
   } deriving (Show)

data Triangle = Triangle Vertex Vertex Vertex deriving (Show)

instance Intersectable Triangle where
   intersect (Triangle v1 v2 v3) r@(Ray ro rd tmin tmax)
      | divisor == 0 = Nothing
      | b1 < 0 || b1 > 1 = Nothing
      | b2 < 0 || b1 + b2 > 1 = Nothing
      | t < tmin || t > tmax = Nothing
      | otherwise = Just (t, DifferentialGeometry (positionAt r t) n)
      where
            n = normalize $ cross e2 e1
            t = (dot e2 s2) * invDiv
            b2 = (dot rd s2) * invDiv -- second barycentric
            s2 = cross d e1
            b1 = (dot d s1) * invDiv -- first barycentric
            d = sub ro p1
            invDiv = 1 / divisor
            divisor = dot s1 e1
            s1 = cross rd e2
            e1 = sub p2 p1
            e2 = sub p3 p1
            p1 = vertexPos v1
            p2 = vertexPos v2
            p3 = vertexPos v3

triangulate :: [Vertex] -> [Triangle]
triangulate (v1:v2:v3:xs) = [Triangle v1 v2 v3] ++ (triangulate $ [v1] ++ [v3] ++ xs)
triangulate _ = []
