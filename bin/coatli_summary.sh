#!/bin/bash

file_list=$1
shift

savedir=`pwd`
make_frame_jpegs=no
logfile=

while [ $# -gt 0 ] ; do eval $1 ; shift ; done

[ -s $file_list ] || { echo "No file $file_list" ; exit 1 ; }

go_iter=0
function gonogo() {
    ((go_iter++))
    [ "$((go_iter%NBATCH))" -eq 0 ] && wait
}

file0=`sort $file_list | head -1`
cam=`gethead CCD_NAME $file0 | cut -c1-2`
[ "$cam" ] || cam=`basename $file0 | cut -c17-18`
[ "$filter" ] || filter=`gethead FILTER stack_${cam}.fits`
[ "$filter" ] || filter=w

# cfilter is the calibration filter
cfilter=`gethead CALFILT stack_${cam}.fits`
[ "$cfilter" ] || cfilter=w
if [ "$cfilter" = "w" ]; then
    cfilter="USNO-R"
else
    cfilter="PS1-$cfilter"
fi

dte1=`echo $file0 | sed -e 's/f//g' -e 's/C/ /g' | awk '{print $1}'`
file1=`sort $file_list | tail -1`
dte2=`echo $file1 | sed -e 's/f//g' -e 's/C/ /g' | awk '{print $1}'`

tag=${cam}_$filter
grb_RA=`gethead CRVAL1 stack_${cam}.fits | awk '{printf("%.6f\n",$1)}'`
grb_DEC=`gethead CRVAL2 stack_${cam}.fits | awk '{printf("%.6f\n",$1)}'`

# make a jpg and one with circles
[ -f stack_${cam}.jpg ] && rm stack_${cam}.jpg
file=stack_${cam}.fits
x0=`gethead CRPIX1 $file`; y0=`gethead CRPIX2 $file`
dx0=`gethead NAXIS1 $file`; dy0=`gethead NAXIS2 $file`
radec2xy.py stack_${cam}.fits usno_radec.fits | awk '{if($1>=1 && $1<='$dx0' && $2>=1 && $2<='$dy0') printf("%f %f %.0f_%.1f\n",$1,$2,$3,$4)}' > usno_xy.txt
make_circles.sh stack_${cam}.fits stack_${cam}_radec.txt calfile=stack_${cam}_radec0.txt

nfiles=`cat $file_list | wc -l`
pdir0=photometry_${dte1}_${tag}_${nfiles}
pdir=${savedir}/$pdir0
if [ -d $pdir ]; then
    rm -r ${pdir}/*
else
    mkdir $pdir
fi

if [ "$make_frame_jpegs" = "yes" ]; then
    for file in `cat $file_list`; do
        base=${file%'.fits'}
        make_circles.sh $file ${base}_dir/${base}_radec.txt sz=736 &
        gonogo
    done
    wait; go_iter=0
fi

# get a dss frame
get_dss.sh stack_${cam}.fits dss_base_file=${savedir}/catalogs/dss0.fits

exptime=`gethead EXPTIME stack_${cam}.fits | awk '{printf("%.1f\n",$1)}'`
fwhm=`gethead FWHM stack_${cam}.fits`
maglim=`gethead MAGLIM stack_${cam}.fits`
magzero=`gethead MAGZERO stack_${cam}.fits`

#make a difference image
if [ -f stack_${cam}a.fits -a -f stack_${cam}b.fits ]; then
    fwhm=`gethead FWHM stack_${cam}.fits`
    echo coatli_imsubAB.sh stack_${cam}a.fits stack_${cam}b.fits fwhm=$fwhm
    coatli_imsubAB.sh stack_${cam}a.fits stack_${cam}b.fits fwhm=$fwhm
    [ -f stack_${cam}a.diff.fits ] && fits2jpg.py stack_${cam}a.diff.fits 1024 linvert
fi

fits2jpg.py stack_${cam}a.fits 1024 linvert
fits2jpg.py stack_${cam}b.fits 1024 linvert
fits2jpg.py stack_${cam}.wt.fits 1024
fits2jpg.py maskstack0_${cam}.fits 1024

nx=`gethead NAXIS1 stack_${cam}.fits`
ny=`gethead NAXIS2 stack_${cam}.fits`

#
#make a webpage
#
echo "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">
<HTML><HEAD><TITLE>$dte1 $nfiles $tag redux</TITLE></HEAD>
<script>
function diffImage(src) {
       document.getElementById(\"mainimage\").src = src;
}
</script>
<BODY BGCOLOR=\"#FFFFFF\" TEXT=\"#003300\">
<FONT SIZE=\"+2\" COLOR=\"#006600\">COATLI $cam $filter : RA $grb_RA , Dec $grb_DEC
[N=$nfiles Frame(s), $dte1 - $dte2]</FONT><BR>
<FONT SIZE=\"+1\">
Frame Size: $nx x $ny &nbsp; &nbsp; &nbsp; Exposure Time: $exptime seconds &nbsp; &nbsp; &nbsp;
10-sigma limiting mag: $maglim &nbsp; &nbsp; &nbsp;
Zero-Point: $magzero &nbsp; &nbsp; &nbsp;
FWHM: $fwhm pixels </FONT><P>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}_circles.jpg\")>Standard view</Button>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}.jpg\")>Image without circles</BUTTON>" >> index.html
[ -f dss.jpg ] && echo "<BUTTON ONCLICK=diffImage(\"${pdir0}/dss.jpg\")>DSS image</BUTTON>" >> index.html
echo "<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}.wt.jpg\")>Weight image</BUTTON>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}_mask.jpg\")>Mask image</BUTTON>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}a.jpg\")>First N/2 frames</BUTTON>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}b.jpg\")>Second N/2 frames</BUTTON>" >> index.html
[ -f stack_${cam}a.diff.jpg ] && echo "<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}.diff.jpg\")>Difference image</BUTTON>" >> index.html

echo "<BR><IMG SRC=\"${pdir0}/stack_${dte1}_${tag}_circles.jpg\" ID=\"mainimage\" USEMAP=\"#stack_${cam}_circles.map\">" >> index.html
sed \$d stack_${cam}_circles.map | sed -e "s/lc_/${pdir0}\/lc_/g" >> index.html

echo "</map><BR>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}_circles.jpg\")>Standard view</Button>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}.jpg\")>Image without circles</BUTTON>" >> index.html
[ -f dss.jpg ] && echo "<BUTTON ONCLICK=diffImage(\"${pdir0}/dss.jpg\")>DSS image</BUTTON>" >> index.html
echo "<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}.wt.jpg\")>Weight image</BUTTON>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}_mask.jpg\")>Mask image</BUTTON>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}a.jpg\")>First N/2 frames</BUTTON>
<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}b.jpg\")>Second N/2 frames</BUTTON>" >> index.html
[ -f stack_${cam}a.diff.jpg ] && echo "<BUTTON ONCLICK=diffImage(\"${pdir0}/stack_${dte1}_${tag}.diff.jpg\")>Difference image</BUTTON><P>" >> index.html


echo "<HTML><HEAD><TITLE>$dte1 $nfiles $tag redux</TITLE></HEAD><BODY BGCOLOR=\"#FFFFFF\" TEXT=\"#003300\">
<FONT SIZE=\"+1\" COLOR=\"#006600\">Sources not in USNO-B1(<A HREF=\"source_fitting_${dte1}_${tag}.jpg\" TARGET=\"_blank\"> Variability plot </A>):</FONT><BR><P><PRE>
#ID        RA          Dec           X            Y           mag         dmag            FWHM    Dist.  Flags" > new_sources.html

#
# go from radec.txt and radec0.txt to radec.tmp to radec0.tmp
#
# start by adding distance column

grep '#' stack_${cam}_radec.txt > stack_${cam}_radec.tmp
grep '#' stack_${cam}_radec0.txt > stack_${cam}_radec0.tmp
pos_err0=`gethead SEXALUN stack_${cam}.fits`
if [ "$pos_err0" ]; then
    pos_err1=`echo $pos_err0 | awk '{s=3600.*$1; printf("%.1f\n",sqrt(1+s*s))}'`
    sx0=`gethead SEXX0 stack_${cam}.fits`
    sy0=`gethead SEXY0 stack_${cam}.fits`
    ps=`gethead CD1_1 CD1_2 stack_${cam}.fits | awk '{printf("%.2f\n",sqrt($1*$1+$2*$2)*3600.)}'`

    grep -v '#' stack_${cam}_radec.txt | awk '{x=$8;y=$9; dx=x-'$sx0'; dy=y-'$sy0'; dis=sqrt(dx*dx+dy*dy)*'$ps'; printf("%s %8.1f\n",$0,dis)}' >> stack_${cam}_radec.tmp
    grep -v '#' stack_${cam}_radec0.txt | awk '{x=$8;y=$9; dx=x-'$sx0'; dy=y-'$sy0'; dis=sqrt(dx*dx+dy*dy)*'$ps'; printf("%s %8.1f\n",$0,dis)}' >> stack_${cam}_radec0.tmp
else
    grep -v '#' stack_${cam}_radec.txt | awk '{printf("%s %8.1f\n",$0,0.0)}' >> stack_${cam}_radec.tmp
    grep -v '#' stack_${cam}_radec0.txt | awk '{printf("%s %8.1f\n",$0,0.0)}' >> stack_${cam}_radec0.tmp
fi

if [ -s fading_sources.txt ]; then
    grep '#' stack_${cam}_radec.tmp > stack_${cam}_radec.tmp1
    for id in `awk '{if($1<0) print $1}' fading_sources.txt`; do
        grep -v '#' stack_${cam}_radec.tmp | awk '{if($15=='$id') print $0,"fading_source"}'
    done > tmp$$.txt
    cat stack_${cam}_radec.tmp tmp$$.txt | grep -v '#' | sort -ur -k 3 | awk '{if($1!=l) print; l=$1}' | sort -n -k 3 >> stack_${cam}_radec.tmp1
    rm tmp$$.txt
    mv stack_${cam}_radec.tmp1 stack_${cam}_radec.tmp
fi

if [ -s stack_${cam}_radec.txt.matched.txt ]; then
    grep '#' stack_${cam}_radec.tmp > stack_${cam}_radec.tmp1
    for id in `awk '{if($15<0) print $15}' stack_${cam}_radec.txt.matched.txt`; do
        grep -v '#' stack_${cam}_radec.tmp | awk '{if($15=='$id') print $0,"ps1_source_not_in_usno"}'
    done > tmp$$.txt
    cat stack_${cam}_radec.tmp tmp$$.txt | grep -v '#' | sort -ur -k 3 | awk '{if($1!=l) print; l=$1}' | sort -n -k 3 >> stack_${cam}_radec.tmp1
    rm tmp$$.txt
    mv stack_${cam}_radec.tmp1 stack_${cam}_radec.tmp
fi

nnew=`grep -v '#' stack_${cam}_radec.tmp | wc -l`
grep -v '#' stack_${cam}_radec.tmp | sort -n -k 16 | awk '{if (system("[ -f lc_"$15".jpg ]")) printf("%d\n",$15); else printf("<A HREF=\"lc_%d.jpg\" TARGET=\"_blank\">%d</A>\n",$15,$15)}' > tag_radec.txt
grep -v '#' stack_${cam}_radec.tmp | sort -n -k 16 | awk '{s=""; if(NF>16) {for(i=17;i<=NF;i++) s=s" "$i}; printf("%-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %8.2f %8.1f %s\n",$1,$2,$8,$9,$3,$4,$7,$16,s)}' > rest_radec.txt
paste tag_radec.txt rest_radec.txt >> new_sources.html
echo "</PRE></BODY></HTML>" >> new_sources.html

rm stack_${cam}_radec.tmp

echo "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">
<HTML><HEAD><TITLE>$dte1 $nfiles $tag redux (raw)</TITLE></HEAD>
<BODY BGCOLOR=\"#FFFFFF\" TEXT=\"#003300\">
<FONT SIZE=\"+1\" COLOR=\"#006600\">Sources not in USNO-B1 (uncalibrated photometry):</FONT><BR><P><PRE>
#ID        RA          Dec           X            Y           mag         dmag            FWHM" > index_raw.html
grep -v '#' stack_${cam}_radec_raw.txt | awk '{if (system("[ -f lc_"$15".jpg ]")) printf("%d\n",$15); else printf("<A HREF=\"lc_%d.jpg\" TARGET=\"_blank\">%d</A>\n",$15,$15)}' > tag_radec.txt
grep -v '#' stack_${cam}_radec_raw.txt | awk '{printf("%-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %8.2f\n",$1,$2,$8,$9,$3,$4,$7)}' > rest_radec.txt
paste tag_radec.txt rest_radec.txt >> index_raw.html
echo "</PRE></BODY></HTML>" >> index_raw.html

echo "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\">
<HTML><HEAD><TITLE>$dte1 $nfiles $tag redux (raw)</TITLE></HEAD>
<BODY BGCOLOR=\"#FFFFFF\" TEXT=\"#003300\">
<FONT SIZE=\"+1\" COLOR=\"#006600\">$cfilter Band Photometry (Catalogued Sources,
<A HREF=\"calplot_${dte1}_${tag}a.jpg\" TARGET=\"_blank\"> Calibration plot </A>,
<A HREF=\"zlf_plot.jpg\" TARGET=\"_blank\"> Sensitivity plot </A>):</FONT><BR><P><PRE>
#ID        RA          Dec           X            Y           mag         dmag            FWHM    Dist.   Flags" > catalogued_sources.html

grep '#' stack_${cam}_radec0.tmp > stack_${cam}_radec0.tmp1
grep -v '#' stack_${cam}_radec0.tmp | awk '{if($15<0) print $0,"usno_high_pm"; else print}' >> stack_${cam}_radec0.tmp1
mv stack_${cam}_radec0.tmp1 stack_${cam}_radec0.tmp

if [ -s fading_sources.txt ]; then
    grep '#' stack_${cam}_radec0.tmp > stack_${cam}_radec0.tmp1
    for id in `awk '{print $1}' fading_sources.txt`; do
        grep -v '#' stack_${cam}_radec0.tmp | awk '{if($15=='$id') print $0,"fading_source"}'
    done > tmp$$.txt
    cat stack_${cam}_radec0.tmp tmp$$.txt | grep -v '#' | sort -ur -k 3 | awk '{if($1!=l) print; l=$1}' | sort -n -k 3 >> stack_${cam}_radec0.tmp1
    mv stack_${cam}_radec0.tmp1 stack_${cam}_radec0.tmp
    rm tmp$$.txt
fi

if [ -s stack_${cam}_radec0.txt.notmatched.txt ]; then
    grep '#' stack_${cam}_radec0.tmp > stack_${cam}_radec0.tmp1
    for id in `awk '{print $15}' stack_${cam}_radec0.txt.notmatched.txt`; do
        grep -v '#' stack_${cam}_radec0.tmp | awk '{if($15=='$id') print $0,"usno_source_not_in_ps1"}'
    done > tmp$$.txt
    cat stack_${cam}_radec0.tmp tmp$$.txt | grep -v '#' | sort -ur -k 3 | awk '{if($1!=l) print; l=$1}' | sort -n -k 3 >> stack_${cam}_radec0.tmp1
    rm tmp$$.txt
    mv stack_${cam}_radec0.tmp1 stack_${cam}_radec0.tmp
fi

nold=`grep -v '#' stack_${cam}_radec0.tmp | wc -l`
grep -v '#' stack_${cam}_radec0.tmp | sort -n -k 16 | awk '{if (system("[ -f lc_"$15".jpg ]")) printf("%d\n",$15); else printf("<A HREF=\"lc_%d.jpg\" TARGET=\"_blank\">%d</A>\n",$15,$15)}' > tag_radec0.txt
grep -v '#' stack_${cam}_radec0.tmp | sort -n -k 16 | awk '{s=""; if(NF>16) {for(i=17;i<=NF;i++) s=s" "$i}; printf("%-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %8.2f %8.1f %s\n",$1,$2,$8,$9,$3,$4,$7,$16,s)}' > rest_radec0.txt
paste tag_radec0.txt rest_radec0.txt >> catalogued_sources.html
echo "</PRE></BODY></HTML>" >> catalogued_sources.html
rm stack_${cam}_radec0.tmp

# if there's source error region and report sources in there first
if [ "$pos_err0" ]; then
    cat new_sources.html catalogued_sources.html | grep -v '#' > index.tmp1
    pos_err=`echo $pos_err0 | awk '{printf("%.1f\n",3600.*$1)}'`
    pos_err1=`echo $pos_err0 | awk '{s=3600.*$1; printf("%.1f\n",sqrt(1+s*s))}'`
    ra0=`gethead SEXALRA stack_${cam}.fits | awk '{printf("%.6f\n",$1)}'`
    dec0=`gethead SEXALDE stack_${cam}.fits | awk '{printf("%.6f\n",$1)}'`
    echo "<FONT SIZE=\"+2\" COLOR=\"#006600\"> Sources within $pos_err arcsec from center: $ra0 , $dec0 </FONT><BR><P><PRE>" >> index.html
    grep '#ID' catalogued_sources.html | awk '{print;exit}' >> index.html
    grep -v '#' index.tmp1 | awk '{if($2~/HREF/) dis=$11; else dis=$9; if (dis<'$pos_err1' && NF>10) print}' | sed -e "s/lc_/${pdir0}\/lc_/g" >> index.html
    echo "</PRE><P><HR>" >> index.html
    rm index.tmp1
fi

echo "<FONT SIZE=\"+1\" COLOR=\"#006600\"><A HREF=\"${pdir0}/new_sources.html\" TARGET=\"_blank\">$nnew Sources not in USNO-B1</A>
(<A HREF=\"${pdir0}/source_fitting_${dte1}_${tag}.jpg\" TARGET=\"_blank\"> Variability plot </A>)</FONT><BR><P>
<FONT SIZE=\"+1\" COLOR=\"#006600\"><A HREF=\"${pdir0}/catalogued_sources.html\" TARGET=\"_blank\">$nold Catalogued Sources</A>
($cfilter Band Photometry, <A HREF=\"${pdir0}/calplot_${dte1}_${tag}a.jpg\" TARGET=\"_blank\"> Calibration plot </A>,
<A HREF=\"${pdir0}/zlf_plot.jpg\" TARGET=\"_blank\"> Sensitivity plot </A>)</FONT><BR><P>" >> index.html

echo "</PRE><HR><FONT SIZE=\"+1\" COLOR=\"#006600\">$cfilter Band Photometry (Catalogued Sources, uncalibrated photometry):</FONT><BR><P><PRE>
#ID        RA          Dec           X            Y           mag         dmag            FWHM" >> index_raw.html
grep -v '#' stack_${cam}_radec0_raw.txt | awk '{if (system("[ -f lc_"$NF".jpg ]")) printf("%d\n",$NF); else printf("<A HREF=\"lc_%d.jpg\" TARGET=\"_blank\">%d</A>\n",$NF,$NF)}' > tag_radec0.txt
grep -v '#' stack_${cam}_radec0_raw.txt | awk '{printf("%-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %-12.6f %8.2f\n",$1,$2,$8,$9,$3,$4,$7)}' > rest_radec0.txt
paste tag_radec0.txt rest_radec0.txt >> index_raw.html
echo "</PRE></BODY></HTML>" >> index_raw.html

dmag0=`gethead CALERR stack_${cam}.fits`
echo "<A HREF=\"${pdir0}/photometry_${dte1}_${tag}.fits\" TARGET=\"_blank\">All Source Photometry.</A><BR>
Note: all photometric errors include a $dmag0 calibration error term added in quadrature.
The uncalibrated photometry is <A HREF=\"${pdir0}/stack_${dte1}_${tag}_${nfiles}_raw.html\" TARGET=\"_blank\">here.</A>" >> index.html

if [ "$make_frame_jpegs" = "yes" ]; then
    echo "<HR> Individual Frame JPEGs:<BR>" >> index.html
    ls f20*circles.jpg | awk '{printf("<A HREF=\"'$pdir0'/%s\" TARGET=\"_blank\">%03d</A> ",$1,NR); if(NR%30==0) printf("<BR>\n")}END{printf("\n")}' >> index.html
fi

upt=`uptime`
echo $upt

dte=`date -u`
cp $logfile ${savedir}/stack_${dte1}_${tag}_${nfiles}.log
echo "<HR WIDTH=\"100%\"> $task_tot 
<A HREF=\"stack_${dte1}_${tag}_${nfiles}.log\" target=\"_blank\">logfile</A>
<A HREF=\"stack_${dte1}_${tag}.fits.fz\" target=\"_blank\">stackfile</A>
<A HREF=\"stack_${dte1}_${tag}.wt.fits.fz\" target=\"_blank\">weightile</A><BR>
$upt <BR> Last Updated: $dte (natbutler@asu.edu)</BODY></HTML>" >> index.html

#
# ship out all the summary files
#
mv index.html ${savedir}/stack_${dte1}_${tag}_${nfiles}.html
[ -f index_raw.html ] && mv index_raw.html ${pdir}/stack_${dte1}_${tag}_${nfiles}_raw.html
[ -f new_sources.html ] && mv new_sources.html ${pdir}/new_sources.html
[ -f catalogued_sources.html ] && mv catalogued_sources.html ${pdir}/catalogued_sources.html
rm ${savedir}/current.html 2>/dev/null
ln -s ${savedir}/stack_${dte1}_${tag}_${nfiles}.html ${savedir}/current.html

cp stack_${cam}_radec.txt ${pdir}/stack_${dte1}_${tag}_radec.txt
cp stack_${cam}_radec0.txt ${pdir}/stack_${dte1}_${tag}_radec0.txt
cp lc_*.jpg lc_*.txt $pdir 2>/dev/null
mv f20*circles.jpg $pdir 2>/dev/null
mv stack_${cam}.jpg ${pdir}/stack_${dte1}_${tag}.jpg
[ -f stack_${cam}a.diff.jpg ] && mv stack_${cam}a.diff.jpg ${pdir}/stack_${dte1}_${tag}.diff.jpg
mv stack_${cam}.wt.jpg ${pdir}/stack_${dte1}_${tag}.wt.jpg
mv stack_${cam}a.jpg ${pdir}/stack_${dte1}_${tag}a.jpg
mv stack_${cam}b.jpg ${pdir}/stack_${dte1}_${tag}b.jpg
mv maskstack0_${cam}.jpg ${pdir}/stack_${dte1}_${tag}_mask.jpg
mv stack_${cam}_circles.jpg ${pdir}/stack_${dte1}_${tag}_circles.jpg
cp calplot.jpg ${pdir}/calplot_${dte1}_${tag}a.jpg
cp source_fitting.txt.jpg ${pdir}/source_fitting_${dte1}_${tag}.jpg
cp zlf_plot.jpg $pdir
cp photometry.fits ${pdir}/photometry_${dte1}_${tag}.fits
cp dss.jpg $pdir

rm stack_${cam}.fits.fz stack_${cam}.wt.fits.fz 2>/dev/null
fpack stack_${cam}.fits &
fpack stack_${cam}.wt.fits &
wait

mv stack_${cam}.fits.fz ${savedir}/stack_${dte1}_${tag}.fits.fz
mv stack_${cam}.wt.fits.fz ${savedir}/stack_${dte1}_${tag}.wt.fits.fz

rm phot$$.tmp0 phot$$.tmp1 thumb_*.fits thumb_*.map stack_*.map usno_xy.txt 2>/dev/null
