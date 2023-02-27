#!/usr/bin/python3
"""
 fits2jpg.py fitsfile [size] [noinvert]
"""

import sys,os

from PIL import Image

from astropy.io.fits import getdata
from numpy.random import rand
from numpy import sqrt,log,array

def usage():
    print (__doc__)
    sys.exit()

def fits2jpg(file0,nsample=50000,out_size=1024,wt_min=1.e-3,invert=True,logscale=False):
    """
    """
    file1=file0.replace('.fits','.jpg')

    outfile=file0.replace('.fits','.jpg')
    wfile=file0.replace('.fits','.wt.fits')
    sys.stderr.write("""Creating %s from %s ...\n""" % (outfile,file0))

    x=getdata(file0)
    a,b=x.shape
    n=a*b

    if (os.path.exists(wfile)):
        wt = getdata(wfile)
        h = wt>wt_min
        x[~h]=0
        x[h]*=sqrt(wt[h])

    if (nsample>n): nsample=n
    xind = (rand(nsample)*(a-1)+1).astype('int32')
    yind = (rand(nsample)*(b-1)+1).astype('int32')

    # summary jpg images
    x1 = x[xind,yind]
    s= x1.argsort()
    s1,s2 = s[int(0.25*nsample)],s[int(0.95*nsample)]
    x1,x2 = x1[s1],x1[s2]

    if (x2>x1):
        if (logscale): y = 255.*log( 1+(x.clip(x1,10*x2)-x1)/(x2-x1) ) / log( 1+(10*x2-x1)/(x2-x1) )
        else: y = 255.*(x.clip(x1,x2)-x1)/(x2-x1)
    else: y=255.*(x-x.min())/(x.max()-x.min())

    if (invert): y = 255.-y
    if (a!=out_size):
        nx,ny = out_size,int(round(1.*out_size*a/b))
        sys.stderr.write("""Resizing Image %s to %dx%d\n""" % (file1,nx,ny))
        y = array(Image.fromarray(obj=y, mode='F').resize(size=(nx,ny), resample=Image.BICUBIC))

    Image.fromarray(obj=y[::-1], mode='F').convert('L').save(file1,format = 'jpeg')


if __name__ == "__main__":
    """
    """
    if (len(sys.argv)<2): usage()

    file0=sys.argv[1]
    if (os.path.exists(file0)==False): usage()

    sz=1024
    if (len(sys.argv)>2): sz=int(sys.argv[2])

    invert=False
    logscale=False
    if (len(sys.argv)>3):
        if(sys.argv[3]=="invert"): invert=True
        elif(sys.argv[3]=="linvert"): invert,logscale = True,True
        else: logscale = True

    fits2jpg(file0,out_size=sz,invert=invert,logscale=logscale)
