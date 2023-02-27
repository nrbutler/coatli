#!/usr/bin/python3
"""
 coatli_lc_plots.py photfile <outfile>
"""
import sys,os
from astropy.io.fits import getheader,getdata
from numpy import loadtxt,sqrt,median,log10,where,ones,zeros

import matplotlib as mpl
mpl.use('Agg')

from matplotlib.pyplot import plot,xlabel,ylabel,savefig,ylim,xlim,errorbar,clf,title,legend,annotate,semilogx

from linfit import linfit

def usage():
    print (__doc__)
    sys.exit()


def get_non_overlapping(image_id,parent_id,nchildren):
    """
    find non-time-overlapping images (image_id), given an observed lightcurve
    """
    n1=len(image_id)
    bad_parent = zeros(n1,dtype='bool')
    non_overlapping = ones(n1,dtype='bool')

    #check that all children have parents
    for i in range(n1):
        if (parent_id[i]==0): continue
        if ( (image_id==parent_id[i]).sum()==0 ): non_overlapping[i]=False

    #check that all of the children are present
    for i in range(n1-1,-1,-1):
        if (nchildren[i]<=1): continue
        h1 = (parent_id==image_id[i])
        if ( h1.sum()==nchildren[i] ): non_overlapping[i],bad_parent[i] = False,True
        else: non_overlapping[h1] = False

    # need to get rid of all ancestors of non_overlapping sources
    for i in range(n1):
        if (nchildren[i]<=1): continue
        h1 = parent_id==image_id[i]
        # are any children bad parents?
        if (bad_parent[h1].sum()>0): bad_parent[i]=True

    non_overlapping[bad_parent] = False

    return non_overlapping


def lc_plots_coatli(photfile,outfile,cfilter='USNO-R(AB)'):
    """
       do some fitting and plotting
    """
    hdr=getheader(photfile)
    t0=hdr['TRIGTM']
    cfilter=hdr['CFILTER']

    # read in the summary of images reduced (ignoring stack)
    imdata=getdata(photfile,1)
    t10,t20,dt0 = imdata['DATE-OBS'][0], imdata['DATE-OBS'][0],imdata['dt'][0]
    imdata=imdata[1:]

    times,times1,expos = imdata['DATE-OBS'], imdata['DATE-OBS'],imdata['dt']
    t,t1 = imdata['T0'],imdata['T1']
    gps = 0.5*(t+t1)

    gps0=0.
    if (gps.min()<0): gps0 -= t.min()

    gps/=3600.
    expos/=3600.

    epoch,nchild,pid = imdata['IMID'],imdata['IMNUM'],imdata['IMPID']

    #number of images (excluding final stack)
    n0=len(epoch)

    # read in the summary of sources detected
    srcdata=getdata(photfile,2)

    idx_ar,mag0_ar,dmag0_ar,ra0_ar,dec0_ar = srcdata['SRCID'],srcdata['mag'],srcdata['dmag'],srcdata['RA'],srcdata['DEC']

    #number of sources
    m0=len(idx_ar)

    # read in the lightcurve data
    data = getdata(photfile,3)

    ofile=open(outfile,'w')
    ofile.write("#  id     slope      dslope       chi2/nu\n")

    for i in range(m0):
        j = data[:,i,3]>0
        if (j.sum()<=1): continue

        id0,mag0,dmag0,ra0,dec0=idx_ar[i],mag0_ar[i],dmag0_ar[i],ra0_ar[i],dec0_ar[i]

        t,dt,t1,t2 = gps[j],expos[j],times[j],times1[j]

        r,d,m,dm,f,exptime = data[j,i].T

        n = epoch[j]
        non_overlapping = get_non_overlapping(n,pid[j],nchild[j])

        j=dm<999
        j0=non_overlapping

        j1=j*j0
        if (j1.sum()<2): continue
        j2=(~j)*j0
        dm[j2] = 0.5; m[j2] += 0.5

        clf()
        errorbar(t[j0],m[j0],xerr=dt[j0]/2.,yerr=dm[j0],marker='o',capsize=0,linestyle='None',markersize=3,mew=1)
        ylim((m[j0].max()+0.5,m[j0].min()-0.5))
        plot (t[j2],m[j2]+0.5,'bv')
        plot (t[j2],m[j2]-0.5,'bo')

        x=-2.5*log10(t)
        res = linfit(x[j1],m[j1],dy=dm[j1],slope_prior_err=1.)
        sig = (m[j1]-res[0]-res[1]*x[j1]).std()
        if (sig<0.01): sig=0.01
        var = dm[j1]**2 + sig**2

        xm = x[j1].mean(); ym = m[j1].mean()
        res = linfit(x[j1]-xm,m[j1]-ym,dy=sqrt(var),slope_prior_err=1.)
        slp=res[1]
        dslp=sqrt(res[2][1][1])

        dt1 = dt[j1].max()
        dt2 = dt[j1].sum()-dt1
        if(dt1>10*dt2): slp=0.

        # handle over-fitting
        if (j1.sum()<=2):
            chi2=0.
            if (slp<0): slp=min(slp+dslp,0.)
            else: slp=max(slp-dslp,0.)
        else:
            chi2 = ( ((m[j1]-ym-res[0]-res[1]*(x[j1]-xm))/dm[j1])**2 ).sum()/(j1.sum()-2)
            slp /= 1.+dslp**2*chi2
            dslp /= 1.+dslp**2*chi2

        ofile.write("""%5d %10.4f %10.4f %10.2f\n""" % (id0,slp,dslp,chi2))

        ii = t[j1].argsort()
        plot (t[j1][ii],res[0]+slp*(x[j1][ii]-xm)+ym,label="""%.4f +/- %.4f""" % (slp,dslp))
        legend()

        d0 = expos.min()
        xlim((gps.min()-d0,gps.max()+d0))
        xlabel("""Time Since %s - %.2f [hours]""" % (t0,gps0/3600.),fontsize=16)
        ylabel(cfilter,fontsize=16)
        title("""Light Curve for Source %d (RA=%.6f, Dec=%.6f, Mag=%.1f)""" % (id0,ra0,dec0,mag0))
        savefig("""lc_%d.jpg""" % id0)

        of = open("""lc_%d.txt""" % id0,'w')
        of.write("""# imid time1 time2 exposure mag dmag non_overlapping?\n""")
        of.write("""0 %s %s %.1f %.4f %.4f 0\n""" % (t10,t20,dt0,mag0,dmag0))
        for ii in range(len(n)):
            of.write("""%d %s %s %.1f %.4f %.4f %d\n""" % (n[ii],t1[ii],t2[ii],exptime[ii],m[ii],dm[ii],int(non_overlapping[ii])))

        of.close()

    ofile.close()

    i,s,ds,c2=loadtxt(outfile,unpack=True,ndmin=2)
    j=c2>0
    if (j.sum()>0):
        i,s,ds,c2 = i[j],s[j],ds[j],c2[j]
        clf()
        x0,x1 = c2.min()*0.8,c2.max()*1.2
        y0,y1 = (s-ds).min()-0.1,(s+ds).max()+0.1
        errorbar(c2,s,yerr=ds,xerr=0*s,marker='o',capsize=0,linestyle='None',markersize=5,mew=1)
        plot ([x0,x1],[0,0],'k:'); plot ([1,1],[y0,y1],'k:')
        xlim((x0,x1)); ylim((y0,y1))
        xlabel(r'Badness of Fit ($\chi^2/\nu$)',fontsize=18)
        ylabel("Powerlaw Temporal Index",fontsize=18)
        semilogx()
        k = where( (s+2*ds<0.)*(s<-0.2) )[0]

        if (len(k)>0):

            ffile=open('fading_sources.txt','w')
            for k0 in k:
                annotate("""%d""" % i[k0],[c2[k0]*1.2,s[k0]],fontsize=18)
                ffile.write("""%d %f %f %f\n""" % (i[k0],s[k0],ds[k0],c2[k0]))

            ffile.close()


        savefig(outfile+'.jpg')


if __name__ == "__main__":
    """
    make summary photometry plots
    """
    if (len(sys.argv)<2): usage()

    infile=sys.argv[1]
    if (os.path.exists(infile)==False): usage()

    outfile='source_fitting.txt'
    if (len(sys.argv)>2): outfile=sys.argv[2]

    lc_plots_coatli(infile,outfile)
