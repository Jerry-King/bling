#!BPY
# -*- coding: utf-8 -*-

"""
Name: 'Bling (.bling)...'
Blender: 249
Group: 'Export'
Tooltip: 'Save a Bling File'
"""

import Blender
from Blender import Mesh, Scene, Window, sys, Image, Draw, Types, Lamp, Mathutils, Material

import math
from Blender.Mathutils import *
from Blender.Material import *

def writeMatrix(o, m) :
   m1 = m.copy().transpose()
   o.write("transform {\n")
   o.write("   identity\n")
   o.write("   matrix {\n")
   o.write("      m %.6f %.6f %.6f %.6f\n" % (m1[0][0], m1[0][1], m1[0][2], m1[0][3]))
   o.write("      m %.6f %.6f %.6f %.6f\n" % (m1[1][0], m1[1][1], m1[1][2], m1[1][3]))
   o.write("      m %.6f %.6f %.6f %.6f\n" % (m1[2][0], m1[2][1], m1[2][2], m1[2][3]))
   o.write("      m %.6f %.6f %.6f %.6f\n" % (m1[3][0], m1[3][1], m1[3][2], m1[3][3]))
   o.write("   }\n")
   o.write("}\n")
   
def writeCamera(o, scene) :
   camobj = scene.objects.camera
   camera = Blender.Camera.Get()[0]
   
   o.write("transform { lookAt {\n")
   mat = camobj.getMatrix()
   
   eyeV    = Mathutils.Vector([0, 0,  0, 1])
   targetV = Mathutils.Vector([0, 0, -1, 1])
   upV     = Mathutils.Vector([0, 1,  0, 0])
	
   eyeV    = eyeV * mat
   targetV = targetV * mat
   upV     = upV * mat
   
   
   # eye position can just be read out of the matrix
   w = mat[3][3]
   eye = (mat[3][0] / w, mat[3][1] / w, mat[3][2] / w)
   o.write("   pos %f %f %f\n" % (eyeV.x, eyeV.y, eyeV.z))
   
   # get the dir vector (camera looking down z)
   d = (mat[2][0], mat[2][1], mat[2][2])
   
   print (d)
   print (d[0])
   
   # look is just the eye position - the direction
   look = (eye[0] - d[0], eye[1] - d[1], eye[2] - d[2])
   o.write("   look %f %f %f\n" % (targetV.x, targetV.y, targetV.z))
   
   # up vector can just be read out of the matrix (y axis)
   up = (mat[1][0], mat[1][1], mat[1][2])
   o.write("   up %f %f %f\n" % (upV.x, upV.y, upV.z))
   o.write("}}\n\n")
   
   o.write("camera {\n")
   o.write("   perspective")
   
   factor = 1
   fov = 360.0 * math.atan(factor * 16.0 / camera.lens) / math.pi
   o.write("   fov %f\n" % fov)
   
   o.write("   lensRadius 0\n")
   o.write("   focalDistance 10 }\n\n")
   
   o.write("transform { identity }\n\n")
   
def writeMaterial(o, mat) :
   o.write("material {\n")
   d = mat.rgbCol
   s = mat.specCol
   
   if (mat.diffuseShader == Shaders.DIFFUSE_LAMBERT and
       mat.specShader == Shaders.SPEC_BLINN) :

      o.write("\tplastic\n")
      o.write("\tkd { constant rgb %f %f %f }\n" % (d[0], d[1], d[2]))
      o.write("\tks { constant rgb %f %f %f }\n" % (s[0], s[1], s[2]))
      h = (512 - float(mat.hard)) / 511
      o.write("\trough { constant %f }\n" % (h * h))
   else :
      o.write("\t# unknown material type, using matte\n")
      o.write("\tmatte\n")
      o.write("\tkd { constant rgb %f %f %f }\n" % (d[0], d[1], d[2]))
      o.write("\tsigma { constant 0 }\n")
      
   o.write("}\n")
          
def writeDefaultMaterial(o) :
   o.write("material { matte kd { constant ")
   o.write("rgb 0.8 0.8 0.8  } ")
   o.write("sigma { constant 0.0 } }\n")

def writeMesh(o, obj) :
   o.write("# Mesh " + obj.name + "\n")
   mesh = Mesh.New(obj.name) # Note the "mesh.verts = None" at the end of this if.  Used to clear the new mesh from memory
   mesh.getFromObject(obj, 0, 1)
   mesh.transform(obj.mat, 1)
  # mesh = mesh.getData()
   verts = mesh.verts
   faces = mesh.faces
   
 #  writeMatrix(o, obj.getMatrix())
   
   if len (mesh.materials) > 0 :
      mat = mesh.materials[0]
      writeMaterial(o, mat)
   else :
      writeDefaultMaterial(o)
   
   o.write("shape {\n")
   o.write("   mesh\n")
   o.write("   vertexCount %u\n" % len(verts))
   o.write("   faceCount %u\n" % len(faces))
      
   for v in verts :
      o.write("   v %.6f %.6f %.6f\n" % (v.co[0], v.co[1], v.co[2]))
   
   for face in faces:
      fv = face.v
      o.write("   f ")
      
      if len(fv) == 4:
         o.write("%d %d %d %d\n" % (fv[0].index, fv[1].index, fv[2].index, fv[3].index))
      elif len(fv) == 3:
         o.write("%d %d %d\n" % (fv[2].index, fv[1].index, fv[0].index))
		
   o.write("}\n")
		
def writeLamp(o, obj) :
   lamp = obj.getData()
   
   objmatrix = obj.matrix
   lampV = Mathutils.Vector([0, 0, 0, 1])
   lampV = lampV * objmatrix
   
   p = lamp.energy
   red = lamp.r * p
   green = lamp.b * p
   blue = lamp.b * p
   rgb = (red, green, blue)
   
   if lamp.getType() == Lamp.Types.Lamp :
      o.write("# point lamp %s\n" % str(lamp))
      o.write("light {\n")
      o.write("   point\n")
      o.write("   intensity rgb %f %f %f\n" % rgb)
      o.write("   position %f %f %f\n" % (lampV[0], lampV[1], lampV[2]))
      o.write("}\n")
   
   elif lamp.getType() == Lamp.Types.Area :
      o.write("# area lamp " + str(dir(lamp)) + "\n")

      # first emission spectrum

      o.write("emission { rgb %f %f %f }\n" % rgb)

      # then geometry
      xsize = lamp.areaSizeX * 0.5
      
      if lamp.areaSizeY:
         ysize = lamp.areaSizeY * 0.5
      else:
         ysize = xsize
      
      lampV0 = Mathutils.Vector([-xsize, ysize, 0, 1])
      lampV1 = Mathutils.Vector([ xsize, ysize, 0, 1])
      lampV2 = Mathutils.Vector([ xsize, -ysize, 0, 1])
      lampV3 = Mathutils.Vector([-xsize, -ysize, 0, 1])

      lampV0 = lampV0 * objmatrix
      lampV1 = lampV1 * objmatrix
      lampV2 = lampV2 * objmatrix
      lampV3 = lampV3 * objmatrix

      o.write("shape {\n")
      o.write("   mesh\n")
      o.write("   vertexCount 4\n")
      o.write("   faceCount 1\n")
      o.write("   v %f %f %f\n" % (lampV0[0], lampV0[1], lampV0[2]))
      o.write("   v %f %f %f\n" % (lampV1[0], lampV1[1], lampV1[2]))
      o.write("   v %f %f %f\n" % (lampV2[0], lampV2[1], lampV2[2]))
      o.write("   v %f %f %f\n" % (lampV3[0], lampV3[1], lampV3[2]))
      o.write("   f 3 2 1 0\n")
      o.write("}\n")
      
      # and turn off emission for remaining gemoetry

      o.write("emission { none }\n")
      
   elif lamp.getType() == Lamp.Types.Sun :
      o.write("# Sun Lamp %s\n" % str(lamp))
      o.write("light {\n")
      o.write("   directional\n")
      o.write("   intensity rgb %f %f %f\n" % rgb)
      im = Mathutils.Matrix(obj.getInverseMatrix())
      o.write("   normal %f %f %f\n" % (im[0][2], im[1][2], im[2][2]))
      o.write("}\n")
      
   else :
      o.write("# unsupported lamp type " + str(lamp.getType()) + "\n")
   
def write(filename, scene) :
   out = open(filename, "w")
   writeCamera(out, scene)
   
   objects = scn.objects
   
   for o in objects:
      if o.type == "Mesh" :
         writeMesh(out, o)
      elif o.type == "Lamp" :
         writeLamp(out, o)
      else :
         out.write("# skipped " + o.type + ": " + o.name + "\n")
        
   out.close()

# Blender.Window.FileSelector(write, "Export")

scn = Scene.GetCurrent()

write("/home/trem/test.bling", scn)

