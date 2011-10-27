
module Graphics.Bling.IO.ShapeParser (
   
   pShape, pPrimitive, pGeometry
   
   ) where

import qualified Data.Vector as V

import Graphics.Bling.Primitive
import Graphics.Bling.Shape
import Graphics.Bling.IO.ParserCore
import Graphics.Bling.IO.WaveFront
import Graphics.Bling.Primitive.Bezier
import Graphics.Bling.Primitive.Fractal

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

pPrimitive :: JobParser AnyPrim
pPrimitive = pBlock $ do
   t <- pString
   p <- case t of
      "bezier" -> do
         subdivs <- ws >> namedInt "subdivs"
         patches <- many1 (try pBezierPatch)
         optional ws
         s <- getState
         return $ mkAnyPrim $ tesselateBezier subdivs patches (transform s) (material s)
                
      "julia" -> do
         c <- ws >> pNamedQuat "c"
         e <- ws >> namedFloat "epsilon"
         i <- ws >> namedInt "iterations"
         s <- getState
         return $ mkAnyPrim $ mkFractalPrim (mkJuliaQuat c e i) (material s)
                
      "menger" -> do
         shape <- ws >> pShape
         level <- ws >> namedInt "level"
         s <- getState
         return $ mkAnyPrim $ mkMengerSponge shape (material s) level (transform s)
         
      "shape" -> do
         shp <- ws >> pShape
         s <- getState
         sid <- nextId
         return $ mkAnyPrim $ mkGeom (transform s) False (material s) (emit s) shp sid
         
      "waveFront" -> do
         fname <- ws >> pQString
         m <- parseWaveFront fname
         return $ mkAnyPrim m

      _ -> fail $ "unknown fractal type " ++ t

   return $ p

pNamedQuat :: String -> JobParser Quaternion
pNamedQuat n = do
   string n >> ws
   pQuaternion

pQuaternion :: JobParser Quaternion
pQuaternion = do
   r <- flt
   i <- ws >> pVec
   return $ Quaternion r i

--
-- parsing shapes
--

pShape :: JobParser Shape
pShape = pBlock $ do
   t <- pString
   
   case t of
      "box" -> do
         pmin <- ws >> namedVector "pmin"
         pmax <- ws >> namedVector "pmax"
         return $ mkBox pmin pmax

      "cylinder" -> do
         r <- ws >> namedFloat "radius"
         zmin <- ws >> namedFloat "zmin"
         zmax <- ws >> namedFloat "zmax"
         phiMax <- ws >> namedFloat "phiMax"
         return $ mkCylinder r zmin zmax phiMax

      "disk" -> do
         h <- ws >> namedFloat "height"
         r <- ws >> namedFloat "radius"
         ri <- ws >> namedFloat "innerRadius"
         phiMax <- ws >> namedFloat "phiMax"
         return $ mkDisk h r ri phiMax

      "quad" -> do
         sx <- ws >> flt
         sz <- ws >> flt
         return $ mkQuad sx sz
         
      "sphere" -> do
         r <- ws >> namedFloat "radius"
         return $ mkSphere r

      _ -> fail $ "unknown shape type " ++ t
      
pGeometry :: JobParser ()
pGeometry = pBlock $ do
   t <- many alphaNum
   
   sh <- case t of
      "box" -> do
         pmin <- ws >> namedVector "pmin"
         pmax <- ws >> namedVector "pmax"
         return [mkBox pmin pmax]
         
      "cylinder" -> do
         r <- ws >> namedFloat "radius"
         zmin <- ws >> namedFloat "zmin"
         zmax <- ws >> namedFloat "zmax"
         phiMax <- ws >> namedFloat "phiMax"
         return [mkCylinder r zmin zmax phiMax]

      "disk" -> do
         h <- ws >> namedFloat "height"
         r <- ws >> namedFloat "radius"
         ri <- ws >> namedFloat "innerRadius"
         phiMax <- ws >> namedFloat "phiMax"
         return [mkDisk h r ri phiMax]
         
      "sphere" -> do
         r <- ws >> namedFloat "radius"
         return [mkSphere r]
         
      "mesh" -> pMesh
      
      _ -> fail $ "unknown shape type \"" ++ t ++ "\""
   
   s <- getState
   p <- (flip mapM) sh $ \shp -> do
      sid <- nextId
      return $ mkGeom (transform s) False (material s) (emit s) shp sid
      
   setState s {prims = map MkAnyPrim p ++ (prims s), currId = (currId s) + 1 }

pBezierPatch :: JobParser Patch
pBezierPatch = (flip namedBlock) "p" $ do
   xs <- flt `sepBy` (optional ws >> char ',' >> optional ws)
   optional ws
   
   case mkPatch xs of
        (Right p) -> return p
        (Left err) -> fail $ "error parsing bezier patch: " ++ err

pMesh :: JobParser [Shape]
pMesh = do
   vc <- ws >> (namedInt "vertexCount" <|> fail "vertexCount missing")
   fc <- ws >> (namedInt "faceCount"  <|> fail "faceCount missing")
   vertices <- count vc vertex
   let va = V.fromList vertices
   faces <- (count fc (face va) <|> fail "error parsing faces")
   return (triangulate faces)
   
face :: (V.Vector Vertex) -> JobParser [Vertex]
face vs = do
   _ <- ws >> char 'f'
   many1 $ try $ do
      idx <- ws >> integ
      if idx >= V.length vs
         then fail $ "vertex index " ++ show idx ++ " out of bounds (" ++ show (V.length vs - 1) ++ ")"
         else return $ V.unsafeIndex vs idx

vertex :: JobParser Vertex
vertex = do
   _ <- ws >> char 'v'
   v <- ws >> pVec
   return (Vertex v)
   