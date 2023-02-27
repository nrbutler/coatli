#!/bin/bash

file_list=$1
shift

catdir=

# source detection
do_lightcurves=yes
match_file=usno_radec.fits
detect_thresh=1.0

# base reduction
inst=coatli
ab_offset=0.0

do_dao=yes

while [ $# -gt 0 ] ; do eval $1 ; shift ; done

[ -s $file_list ] || { echo "No file $file_list" ; exit 1 ; }
[ "$catdir" ] || { echo "No catalog dir specified" ; exit 2 ; }

file0=`head -1 $file_list`
[ -f $file0 ] || { echo "Cannot find first file $file0" ; exit 3 ; }
cam=`basename $file0 | cut -c17-18`

dao=
if [ "$do_dao" = "yes" ]; then
    dao=dao
fi

#
# starting work
#

[ -f stack_${cam}.fits ] || { echo "No stack file found, exiting..." ; exit 4 ; }

[ -d stack_${cam}_dir ] && rm -r stack_${cam}_dir
run_astnet_blind.sh stack_${cam}.fits
[ -f stack_${cam}.wcs ] || { echo "No astrometry for stack_${cam}.fits, exiting..." ; exit 5 ; }

go_iter=0
function gonogo() {
    ((go_iter++))
    [ "$((go_iter%NBATCH))" -eq 0 ] && wait
}

if [ -f "${catdir}/usno_radec16_${cam}.fits" ]; then
    echo "Using ${catdir}/usno_radec16_${cam}.fits"
else
    here=`pwd`
    ps=`gethead CD1_1 CD1_2 stack_${cam}.fits | awk '{printf("%.2f\n",sqrt($1*$1+$2*$2)*3600)}'`
    filef=`readlink -f stack_${cam}.fits`
    cd $catdir
    echo grab_usno_local.sh $filef max_offset=0.1 pscale=$ps
    grab_usno_local.sh $filef max_offset=0.1 pscale=$ps
    cd $here
fi
ln -s ${catdir}/usno_radec_${cam}.fits usno_radec.fits 2>/dev/null
ln -s ${catdir}/usno_radec_${cam}.pm.fits usno_radec.pm.fits 2>/dev/null
ln -s ${catdir}/usno_radec16_${cam}.fits usno_radec16.fits 2>/dev/null

#
# do photometry on the stack finding stars present (sfile) and not present (nfile) in USNO
#
[ -d stack_${cam}_dir ] && rm -r stack_${cam}_dir
mkdir stack_${cam}_dir
radec2xy.py stack_${cam}.fits $match_file > stack_${cam}_dir/sky.list

run_sex.sh stack_${cam}.fits $inst $dao -DETECT_THRESH $detect_thresh

filter=`gethead FILTER stack_${cam}.fits`
[ "$filter" ] || filter=w

grb_RA=`gethead CRVAL1 stack_${cam}.fits`
grb_DEC=`gethead CRVAL2 stack_${cam}.fits`

here=`pwd`
cd $catdir
[ -f ps1_dr1_radec.txt ] || grab_ps1_dr1.sh ra=$grb_RA dec=$grb_DEC
cd $here

if [ "$filter" = "w" ]; then
   filter0=$filter
   filter=R
else
   filter=`echo $filter | cut -c2-`
fi
calfile=${catdir}/ps1_dr1_radec${filter}.txt

if [ -f "$calfile" ]; then
    do_match1.py stack_${cam}_dir/stack_${cam}_radec.txt $calfile 18.0 $ab_offset do_plot > stack_${cam}_dir/stack_${cam}.report
else
    filter=$filter0
    calibrate.py stack_${cam}_dir/stack_${cam}_radec.txt stack_${cam}_dir/sky.list 18.0 $ab_offset > stack_${cam}_dir/stack_${cam}.report
fi

# record some statistics
lms=`egrep 'FWHM|10-sigma limiting|Zero' stack_${cam}_dir/stack_${cam}.report | awk '{printf("%f ",$4)}END{printf("\n")}' | awk '{printf("FWHM=%.2f MAGZERO=%.2f MAGLIM=%.2f\n",$1,$2,$3)}'`
sethead $lms stack_${cam}.fits stack_${cam}.wt.fits
mv stack_${cam}_dir/stack_${cam}_radec.txt.photometry.txt_dm.jpg calplot.jpg

# remember which filter we actually used to calibrate
sethead CALFILT=$filter stack_${cam}.fits

cfilter=$filter
if [ "$cfilter" = "w" ]; then
    cfilter="USNO-R"
else
    cfilter="PS1-$cfilter"
fi

sfile=stack_${cam}_radec0.txt
sfile_raw=stack_${cam}_radec0_raw.txt
grep '#' stack_${cam}_dir/stack_${cam}_radec.txt.photometry.txt > $sfile
grep '#' stack_${cam}_dir/stack_${cam}_radec.txt > $sfile_raw
grep -v '#' stack_${cam}_dir/stack_${cam}_radec.txt.photometry.txt | sort -n -k 3 >> $sfile
grep -v '#' stack_${cam}_dir/stack_${cam}_radec.txt | sort -n -k 3 >> $sfile_raw

fwhm=`gethead FWHM stack_${cam}.fits`
[ "$fwhm" ] || fwhm=2.0
match_rad=`echo $fwhm | awk '{if($1<2) print 2.0; else print $1}'`
run_sex.sh stack_${cam}.fits $inst $dao -ASSOCSELEC_TYPE -MATCHED -DETECT_THRESH $detect_thresh -ASSOC_RADIUS $match_rad

mag0=`grep 'Magnitude Offset' stack_${cam}_dir/stack_${cam}.report | awk '{print $3;exit}'`
dmag0=`grep 'Magnitude Offset' stack_${cam}_dir/stack_${cam}.report | awk '{print $5;exit}'`
sethead CALERR=$dmag0 stack_${cam}.fits stack_${cam}.wt.fits
nfile=stack_${cam}_radec.txt
nfile_raw=stack_${cam}_radec_raw.txt
grep '#' stack_${cam}_dir/stack_${cam}_radec.txt > $nfile
grep '#' stack_${cam}_dir/stack_${cam}_radec.txt > $nfile_raw
grep -v '#' stack_${cam}_dir/stack_${cam}_radec.txt | sort -n -k 3 | awk '{print $1,$2,$3+('$mag0'),sqrt($4^2+'$dmag0'^2),$5+('$mag0'),sqrt($6^2+'$dmag0'^2),$7,$8,$9,$10,$11,$12,$13,$14,-NR}' >> $nfile
grep -v '#' stack_${cam}_dir/stack_${cam}_radec.txt | sort -n -k 3 | awk '{print $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,-NR}' >> $nfile_raw
remove_high_props.py $nfile usno_radec.pm.fits
[ -s pm_$nfile ] && cat pm_$nfile >> $sfile
remove_high_props.py $nfile_raw usno_radec.pm.fits
[ -s pm_$nfile_raw ] && cat pm_$nfile_raw >> $sfile_raw

# check for Swift information
file1=`sort -nr $file_list | head -1`
pos_err0=`gethead ALUN $file1 | awk '{printf("%.6f\n",$1)}'`
[ "$pos_err0" ] || pos_err0=`gethead SEXALUN $file1 | awk '{printf("%.6f\n",$1)}'`
if [ "$pos_err0" ]; then
    ps=`gethead CD1_1 CD1_2 stack_${cam}.fits | awk '{printf("%.2f\n",sqrt($1*$1+$2*$2)*3600.)}'`
    ra0=`gethead -c ALRA $file1 | awk '{printf("%.6f\n",$1)}'`
    [ "$ra0" ] || ra0=`gethead -c SEXALRA $file1 | awk '{printf("%.6f\n",$1)}'`
    dec0=`gethead -c ALDE $file1 | awk '{printf("%.6f\n",$1)}'`
    [ "$dec0" ] || dec0=`gethead -c SEXALDE $file1 | awk '{printf("%.6f\n",$1)}'`
    pos_err=`echo $pos_err0 $ps | awk '{printf("%.1f\n",3600.*$1/$2)}'`
    echo $ra0 $dec0 > radec$$.txt
    radec2xy.py stack_${cam}.fits radec$$.txt > xy$$.txt
    x00=`awk '{print $1;exit}' xy$$.txt`
    y00=`awk '{print $2;exit}' xy$$.txt`
    sethead SEXX0=$x00 SEXY0=$y00 SEXERR=$pos_err SEXALUN=$pos_err0 SEXALRA=$ra0 SEXALDE=$dec0 stack_${cam}.fits
    rm xy$$.txt radec$$.txt
fi

# check against ps1
if [ -f "$calfile" ]; then
    rm ${sfile}.matched.txt ${sfile}.notmatched.txt ${nfile}.matched.txt ${nfile}.notmatched.txt 2>/dev/null
    do_match1.py $sfile $calfile > /dev/null 2>&1
    do_match1.py $nfile $calfile > /dev/null 2>&1
fi


#
# do photometry on individual files
#
x0=`gethead CRPIX1 stack_${cam}.fits`; y0=`gethead CRPIX2 stack_${cam}.fits`
cat $sfile $nfile | grep -v '#' | awk '{print $8-('$x0'),$9-('$y0'),$15,$3,$4}' > match_file.xy
cp $file_list r$file_list

# potentially do photometry on sub-stacks, if present
ls stack_20*[0-9].fits >> r$file_list 2>/dev/null
ls stack_${cam}a.fits stack_${cam}b.fits >> r$file_list

for file in `cat r$file_list`; do
    base=${file%'.fits'}
    [ -d "${base}_dir" ] && rm -r ${base}_dir
    mkdir ${base}_dir
    x=`gethead CRPIX1 $file`; y=`gethead CRPIX2 $file`
    awk '{print $1+'$x',$2+'$y',$3,$4,$5}' match_file.xy > ${base}_dir/sky.list
    if [ "$pos_err" ]; then
        x1=`echo $x00 $x0 $x | awk '{printf("%.1f\n",$1-$2+$3)}'`
        y1=`echo $y00 $y0 $y | awk '{printf("%.1f\n",$1-$2+$3)}'`
        sethead SEXX0=$x1 SEXY0=$y1 SEXERR=$pos_err ${base}.fits
    fi
    run_sex.sh ${base}.fits $inst $dao -DETECT_THRESH $detect_thresh &
    gonogo
done
wait; go_iter=0

# calibrate the individual frames
nn=`cat match_file.xy | wc -l`
ref=stack_${cam}_radec0.xy
nx=`gethead NAXIS1 $file0`; ny=`gethead NAXIS2 $file0`
nx0=`gethead NAXIS1 stack_${cam}.fits`; ny0=`gethead NAXIS2 stack_${cam}.fits`
grep -v '#' $sfile | awk '{dx=('$nx0'-'$nx')/2.+10;dy=('$ny0'-'$ny')/2.+10;x=$8;y=$9;if(x>dx && x<'$nx0'-dx && y>dy && y<'$ny0'-dy) print x,y,$NF,$3,$4}' > $ref

for file in `cat r$file_list`; do
    base=${file%'.fits'}
    calibrate.py ${base}_dir/${base}_radec.txt $ref 18.0 0.0 > ${base}_dir/${base}.report &
    gonogo
done
wait; go_iter=0

# record calibration data
echo stack_${cam}.fits > zlf_list$$.txt
cat r$file_list >> zlf_list$$.txt
for file in `cat zlf_list$$.txt`; do
    base=${file%'.fits'}
    rfile=${base}_dir/${base}.report
    dat=`awk '{if ($0~/Median Sextractor FWHM/) f=$4; if ($0~/Median Zero Point/) zp=$4; if($0~/Magnitude Offset/) {m0=$3;dm0=$5}; if ($0~/10-sigma limiting magnitude/) {print t1,t2,f,zp,$4,m0,dm0}}' $rfile`
    echo $dat | awk '{printf("sethead FWHM=%.2f MAGZERO=%.2f MAGLIM=%.2f MAG0=%.6f DMAG0=%.6f '${base}.fits'\n",$1,$2,$3,$4,$5)}' | sh &
    gonogo
done
wait; go_iter=0

# now track the new stars in the individual files
echo "# id ra dec mag dmag fwhm expos" > master_phot_${cam}.txt
grep -v '#' $nfile | awk '{printf("%6d %12.8f %12.8f %12.6f %12.6f %8.2f %12.6f\n",$NF,$1,$2,$3,$4,$7,$14)}' > master_phot_${cam}.tmp
grep -v '#' $sfile | awk '{printf("%6d %12.8f %12.8f %12.6f %12.6f %8.2f %12.6f\n",$NF,$1,$2,$3,$4,$7,$14)}' >> master_phot_${cam}.tmp
sort -n -k 4 master_phot_${cam}.tmp >> master_phot_${cam}.txt

# summary of images used
gethead -a IMID IMNUM IMPID DATE-OBS DATE-OBE EXPTIME FWHM MAGZERO MAGLIM MAG0 DMAG0 stack_${cam}.fits | sed -e 's/-//g' -e 's/://g' > times_$file_list
gethead IMID IMNUM IMPID DATE-OBS DATE-OBE EXPTIME FWHM MAGZERO MAGLIM MAG0 DMAG0 @r$file_list | sort -n -k 2 | sed -e 's/-//g' -e 's/://g' >> times_$file_list

# use these to make a summary fits file photometry.fits
trig_time=`gethead ALEVT $file0 | sed -e 's/-//g' -e 's/://g'`
[ "$trig_time" ] || trig_time=`gethead ALALT $file0 | sed -e 's/-//g' -e 's/://g'`
[ "$trig_time" ] || trig_time=`gethead SEXALT $file0 | sed -e 's/-//g' -e 's/://g'`
[ "$trig_time" ] || trig_time=`gethead SEXALTRT $file0 | sed -e 's/-//g' -e 's/://g'`
[ "$trig_time" ] || trig_time=`gethead SEXALTRT stack_${cam}.fits | sed -e 's/-//g' -e 's/://g'`
[ "$trig_time" ] && sethead SEXALTRT=$trig_time stack_${cam}.fits
[ "$trig_time" ] || trig_time=`gethead DATE-OBS stack_${cam}.fits | sed -e 's/-//g' -e 's/://g'`
echo phot2fits.py times_$file_list master_phot_${cam}.txt $trig_time $cfilter
phot2fits.py times_$file_list master_phot_${cam}.txt $trig_time $cfilter

# make a data quality plot
zlf_plot.py photometry.fits
mv photometry.fits.jpg zlf_plot.jpg

if [ "$do_lightcurves" = "yes" ]; then

    echo coatli_lc_plots.py photometry.fits
    coatli_lc_plots.py photometry.fits

fi

rm -r r$file_list zlf_list$$.txt master_phot_${cam}.tmp 2>/dev/null
