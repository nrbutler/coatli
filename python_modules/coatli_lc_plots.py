#!/usr/bin/python3
"""
 coatli_lc_plots.py photfile <outfile>
"""
import sys,os
from astropy.io.fits import getheader,getdata
from numpy import loadtxt,sqrt,median,log10,where,ones,zeros

import matplotlib as mpl
mpl.use('Agg')

from matplotlib.pyplot import plot,xlabel,ylabel,savefig,ylim,xlim,errorbar,clf,title,legend,annotate,semilogx,subplots,ioff,close
ioff()

from multiprocessing import Pool,Lock

from linfit import linfit

def usage():
    print (__doc__)
    sys.exit()

def init(lock0):
    """
    to avoid drawing more than one lc plot at once
    """
    global lock
    lock = lock0

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


def make_lc_plot(lc_file):
    """
      make an lc jpg from an lc txt file
    """

    n,t,dt,m,dm,olap = loadtxt(lc_file,unpack=True)
    j0 = olap>0

    j=dm<999
    j1=j*j0
    if (j1.sum()<2): return 0
    j2=(~j)*j0
    dm[j2] = 0.5; m[j2] += 0.5

    fig,ax = subplots()
    ax.errorbar(t[j0],m[j0],xerr=dt[j0]/2.,yerr=dm[j0],marker='o',capsize=0,linestyle='None',markersize=3,mew=1)
    ax.set_ylim((m[j0].max()+0.5,m[j0].min()-0.5))
    ax.plot (t[j2],m[j2]+0.5,'bv')
    ax.plot (t[j2],m[j2]-0.5,'bo')

    f = open(lc_file)
    dat = f.readlines()
    f.close()

    slp,dslp,chi2,res0 = dat[4].split()[3:]
    slp,dslp,res0 = float(slp),float(dslp),float(res0)

    ii = t[j1].argsort()    
    x=-2.5*log10(t)
    xm = x[j1].mean(); ym = m[j1].mean()
    ax.plot (t[j1][ii],res0+slp*(x[j1][ii]-xm)+ym,label="""%.4f +/- %.4f""" % (slp,dslp))
    ax.legend()

    x1,x2 = dat[0].split()[2:]
    ax.set_xlim((float(x1),float(x2)))
    ax.set_xlabel(dat[1].strip()[2:],fontsize=16)
    ax.set_ylabel(dat[2].strip()[2:],fontsize=16)
    ax.set_title(dat[3].strip()[2:])

    #lock.acquire()
    fig.savefig(lc_file.replace('.txt','.jpg'))
    #lock.release()

    close(fig)


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

    lc_files = []

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

        ofile.write("""%5d %10.4f %10.4f %10.2f %10.4e\n""" % (id0,slp,dslp,chi2,res[0]))

        d0 = expos.min()
        xlim_use = """# xlim %f %f\n""" % (gps.min()-d0,gps.max()+d0)
        xlabel_use = """# Time Since %s - %.2f [hours]\n""" % (t0,gps0/3600.)
        ylabel_use = '# '+cfilter+'\n'
        title_use = """# Light Curve for Source %d (RA=%.6f, Dec=%.6f, Mag=%.1f)\n""" % (id0,ra0,dec0,mag0)

        lc_file = """lc_%d.txt""" % id0
        of = open(lc_file,'w')
        of.write(xlim_use)
        of.write(xlabel_use)
        of.write(ylabel_use)
        of.write(title_use)
        of.write("""# fitting %5d %10.4f %10.4f %10.2f %10.4e\n""" % (id0,slp,dslp,chi2,res[0]))
        of.write("""# imid time1 time2 exposure mag dmag non_overlapping?\n""")
        of.write("""# overall: 0 %s %s %.1f %.4f %.4f 0\n""" % (t10,t20,dt0,mag0,dmag0))
        for ii in range(len(n)):
            of.write("""%d %.8f %.8f %.4f %.4f %d\n""" % (n[ii],t[ii],dt[ii],m[ii],dm[ii],int(non_overlapping[ii])))

        of.close()
        lc_files.append(lc_file)

    ofile.close()

    lock0 = Lock()
    pool = Pool(initializer=init, initargs=(lock0,))
    pool.map( make_lc_plot, lc_files )

    i,s,ds,c2,norm=loadtxt(outfile,unpack=True,ndmin=2)
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
