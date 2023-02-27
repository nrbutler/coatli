#!/bin/bash

file_list=$1
shift

#matching,wcs
mask_sigma=3.0
bg_order=4

# base reduction
ps=0.000195
inst=coatli
gain=6.2

# to speed up swarping
nbin_group=100

do_nir_sky=yes

while [ $# -gt 0 ] ; do eval $1 ; shift ; done

[ -s $file_list ] || { echo "No file $file_list" ; exit 1 ; }

file0=`head -1 $file_list`
[ -f $file0 ] || { echo "Cannot find first file $file0" ; exit 2 ; }

go_iter=0
function gonogo() {
    ((go_iter++))
    [ "$((go_iter%NBATCH))" -eq 0 ] && wait
}

cam=`basename $file0 | cut -c16-17`
nx=`gethead NAXIS1 $file0`
ny=`gethead NAXIS2 $file0`
cx=`gethead CRPIX1 $file0`
cy=`gethead CRPIX2 $file0`

nstack=`cat $file_list | wc -l`

if [ "$nstack" -gt 0 ]; then

    # now we align the new matched files
    sargs0="-c ${SWARP_DIR}/coatli_redux.swarp -RESAMPLING_TYPE NEAREST -SUBTRACT_BACK N -COMBINE N -HEADER_ONLY Y"
    sargs0="$sargs0 -IMAGEOUT_NAME stack_${cam}.fits -WEIGHTOUT_NAME stack_${cam}.wt.fits -WEIGHT_TYPE NONE"
    rm stack_${cam}.head 2>/dev/null
    echo swarp @$file_list $sargs0 -MEM_MAX 1024 -COMBINE_BUFSIZE 1024
    swarp @$file_list $sargs0 -MEM_MAX 1024 -COMBINE_BUFSIZE 1024
    sethead CD1_1=-$ps CD2_2=$ps stack_${cam}.fits

    if [ -f stack_${cam}.head0 ]; then
        echo "Using existing projection from stack_${cam}.head0"

        ps=`gethead CD1_1 CD1_2 stack_${cam}.head0 | awk '{print sqrt($1*$1+$2*$2)}'`
        ra0=`gethead CRVAL1 stack_${cam}.head0`; dec0=`gethead CRVAL2 stack_${cam}.head0`
        x0=`gethead CRPIX1 stack_${cam}.head0`; y0=`gethead CRPIX2 stack_${cam}.head0`
        ra1=`gethead CRVAL1 stack_${cam}.fits`; dec1=`gethead CRVAL2 stack_${cam}.fits`
        x1=`gethead CRPIX1 stack_${cam}.fits`; y1=`gethead CRPIX2 stack_${cam}.fits`

        dx=`echo $ra1 $ra0 $x1 $x0 | awk '{dx=($1-$2)/'$ps'-($4-$3); if(dx>0) printf("%.0f\n",dx); else print 0}'`
        dy=`echo $dec1 $dec0 $y1 $y0 | awk '{dx=($2-$1)/'$ps'-($4-$3); if(dx>0) printf("%.0f\n",dx); else print 0}'`

        nx0=`gethead NAXIS1 stack_${cam}.fits`
        ny0=`gethead NAXIS2 stack_${cam}.fits`
        x0=`gethead CRPIX1 stack_${cam}.head0 | awk '{print $1+'$dx'}'`
        y0=`gethead CRPIX2 stack_${cam}.head0 | awk '{print $1+'$dy'}'`
        cp stack_${cam}.head0 stack_${cam}.head
        sethead NAXIS1=$nx0 NAXIS2=$ny0 CRPIX1=$x0 CRPIX2=$y0 stack_${cam}.head
    else
        imhead -f stack_${cam}.fits > stack_${cam}.head
        sethead BITPIX=0 stack_${cam}.head
        cp stack_${cam}.head stack_${cam}.head0
    fi

    ra0=`gethead CRVAL1 stack_${cam}.head`
    dec0=`gethead CRVAL2 stack_${cam}.head`
    function copy_files() {
        local file=$1
        cp $file f$file
        local base=${file%'.fits'}
        local wfile=${base}.wt.fits
        cp $wfile f$wfile
        imhead -f $file > f${base}.head1
        local ra1=`gethead CRVAL1 $file`; dec1=`gethead CRVAL2 $file`
        local dx=`echo $ra1 $ra0 | awk '{printf("%.0f\n",($2-$1)/'$ps')}'`
        local dy=`echo $dec1 $dec0 | awk '{printf("%.0f\n",($2-$1)/'$ps')}'`
        local cx1=`echo $cx $dx | awk '{print $1-$2}'`
        local cy1=`echo $cy $dy | awk '{print $1+$2}'`
        local sky=`gethead SKYLEV $file`
        sethead CRVAL1=$ra0 CRVAL2=$dec0 CRPIX1=$cx1 CRPIX2=$cy1 f$file
        sethead BZERO=-$sky f$file
        echo f$file
    }

    for file in `cat $file_list`; do
        copy_files $file &
        gonogo
    done > f$file_list
    wait; go_iter=0

    sort -n f$file_list > f${file_list}.tmp
    mv f${file_list}.tmp f$file_list

    # we need to separate files by exposure time
    gethead EXPTIME @f$file_list | awk '{print $1>"f'$file_list'_"$2".txt"}'
    ls f${file_list}_*.txt

    # split them up to make swarp faster
    for lfile in `ls f${file_list}_*.txt`; do
        nfiles=`cat $lfile | wc -l`
        ngroups=`echo $nbin_group $nfiles | awk '{n=int($2/$1); if(n==0) n=n+1; print n}'`
        awk '{n=int((NR-1)*'$ngroups'/'$nfiles'); print $0>"'$lfile'_"n".txt"}' $lfile
    done

    # build a stack for source masking
    sargs1="-c ${SWARP_DIR}/coatli_redux.swarp -RESAMPLE N -RESAMPLE_SUFFIX .fits -SUBTRACT_BACK N -WEIGHT_SUFFIX .wt.fits"
    nmax=`ls f${file_list}_*.txt_*.txt | wc -l`
    if [ "$nmax" -gt 1 ]; then
        n=0
        rm list$$.txt 2>/dev/null
        for flist in `ls f${file_list}_*.txt_*.txt`; do
            echo stack0_${cam}_${n}.fits >> list$$.txt
            echo swarp @$flist $sargs1 -COMBINE_TYPE CLIPPED -CLIP_SIGMA 10.0 -IMAGEOUT_NAME stack0_${cam}_${n}.fits -WEIGHTOUT_NAME stack0_${cam}_${n}.wt.fits
            swarp @$flist $sargs1 -COMBINE_TYPE CLIPPED -CLIP_SIGMA 10.0 -IMAGEOUT_NAME stack0_${cam}_${n}.fits -WEIGHTOUT_NAME stack0_${cam}_${n}.wt.fits 2>/dev/null &
            gonogo
            n=`expr $n + 1`
        done
        wait; go_iter=0
    else
        cp f${file_list}_*.txt_*.txt list$$.txt
    fi
    cp stack_${cam}.head stack0_${cam}.head
    echo swarp @list$$.txt $sargs1 -COMBINE_TYPE WEIGHTED -IMAGEOUT_NAME stack0_${cam}.fits -WEIGHTOUT_NAME stack0_${cam}.wt.fits -MEM_MAX 1024 -COMBINE_BUFSIZE 1024
    swarp @list$$.txt $sargs1 -COMBINE_TYPE WEIGHTED -IMAGEOUT_NAME stack0_${cam}.fits -WEIGHTOUT_NAME stack0_${cam}.wt.fits -MEM_MAX 1024 -COMBINE_BUFSIZE 1024 2>/dev/null
    rm stack0_${cam}.head list$$.txt 2>/dev/null

    # do a quick background subtraction
    backsub.py stack0_${cam}.fits stack0_${cam}.wt.fits -1

    sat_level=`gethead SATURATE @f$file_list | awk 'BEGIN{s=1.e56}{if($2<s) s=$2}END{print s}'`
    exptime=`gethead EXPTIME @f$file_list | awk '{s=s+$2}END{printf("%f\n", s)}'`
    mgain=`echo $gain $exptime | awk '{print 0.7*$1*$2}'`    # median stack gain
    igain=`echo $gain $exptime | awk '{print $1*$2}'`    # weighted stack gain
    sky0=`gethead SKYLEV @f$file_list | awk '{n=n+1;w0=w0+1/$2}END{print n/w0}'`
    sethead SKYLEV=$sky0 SATURATE=$sat_level EXPTIME=$exptime GAIN=$mgain stack0_${cam}.fits

    # make a source mask
    run_sex.sh stack0_${cam}.fits $inst -CHECKIMAGE_TYPE OBJECTS -CHECKIMAGE_NAME mask.fits -BACK_SIZE 8
    sources2mask.py stack0_${cam}.wt.fits stack0_${cam}_dir/mask.fits maskstack0_${cam}.fits $mask_sigma

    # register that mask to every file
    x0=`gethead CRPIX1 stack0_${cam}.fits`; y0=`gethead CRPIX2 stack0_${cam}.fits`
    nx0=`gethead NAXIS1 stack0_${cam}.fits`; ny0=`gethead NAXIS2 stack0_${cam}.fits`

    # need a source mask for and to determine the background for every file
    function sub_back() {
        local file=$1
        local base=${file%'.fits'}
        local xr=`gethead CRPIX1 $file | awk '{x=int($1-('$x0'));if ('$nx'-x>'$nx0') x='$nx'-'$nx0';printf("%.0f-%.0f\n",1-x,'$nx'-x)}'`
        local yr=`gethead CRPIX2 $file | awk '{y=int($1-('$y0'));if ('$ny'-y>'$ny0') y='$ny'-'$ny0';printf("%.0f-%.0f\n",1-y,'$ny'-y)}'`
        getfits maskstack0_${cam}.fits $xr $yr -o ${base}.wmap_mask.fits
        backsub.py $file ${base}.wmap_mask.fits $bg_order
    }

    for file in `cat f$file_list`; do
        sub_back $file &
        gonogo
    done
    wait; go_iter=0

    if [ "$do_nir_sky" = "yes" ]; then

        # determine an on-chip background
        for file in `cat $file_list`; do
            sky=`gethead SKYLEV $file`
            bs=`echo $sky $sky0 | awk '{printf("%.6f\n",$2/$1)}'`
            sethead BSCALE=$bs f$file
        done

        sargs2="-c ${SWARP_DIR}/coatli_redux.swarp -COMBINE_TYPE MEDIAN -RESAMPLE N -HEADER_SUFFIX .head1 -RESAMPLE_SUFFIX .fits -SUBTRACT_BACK N -WEIGHT_SUFFIX .wmap_mask.fits"
        n=0
        for lfile in `ls f${file_list}_*.txt_*.txt`; do
            echo swarp @$lfile $sargs2 -IMAGEOUT_NAME back_${n}.fits -WEIGHTOUT_NAME back_${n}.wt.fits
            swarp @$lfile $sargs2 -IMAGEOUT_NAME back_${n}.fits -WEIGHTOUT_NAME back_${n}.wt.fits 2>/dev/null &
            gonogo
            n=`expr $n + 1`
        done
        wait; go_iter=0

        n=0
        for lfile in `ls f${file_list}_*.txt_*.txt`; do
            subtract_images.sh back_${n}.fits $lfile
            n=`expr $n + 1`
        done

        sethead BSCALE=1.0 @f$file_list

    fi

    # now create a median stack that will form the basis for a clipped stack
    if [ "$nmax" -gt 1 ]; then
        n=0
        rm list$$.txt 2>/dev/null
        for flist in `ls f${file_list}_*.txt_*.txt`; do
            echo stack1_${cam}_${n}.fits >> list$$.txt
            echo swarp @$flist $sargs1 -COMBINE_TYPE MEDIAN -IMAGEOUT_NAME stack1_${cam}_${n}.fits -WEIGHTOUT_NAME stack1_${cam}_${n}.wt.fits
            swarp @$flist $sargs1 -COMBINE_TYPE MEDIAN -IMAGEOUT_NAME stack1_${cam}_${n}.fits -WEIGHTOUT_NAME stack1_${cam}_${n}.wt.fits 2>/dev/null &
            gonogo
            n=`expr $n + 1`
        done
        wait; go_iter=0
    else
        cp f${file_list}_*.txt_*.txt list$$.txt
    fi
    cp stack_${cam}.head stack1_${cam}.head
    echo swarp @list$$.txt $sargs1 -COMBINE_TYPE WEIGHTED -IMAGEOUT_NAME stack1_${cam}.fits -WEIGHTOUT_NAME stack1_${cam}.wt.fits -MEM_MAX 1024 -COMBINE_BUFSIZE 1024
    swarp @list$$.txt $sargs1 -COMBINE_TYPE WEIGHTED -IMAGEOUT_NAME stack1_${cam}.fits -WEIGHTOUT_NAME stack1_${cam}.wt.fits -MEM_MAX 1024 -COMBINE_BUFSIZE 1024 2>/dev/null
    rm stack1_${cam}.head list$$.txt 2>/dev/null

    sethead SKYLEV=$sky0 SATURATE=$sat_level EXPTIME=$exptime GAIN=$mgain stack1_${cam}.fits

    x0=`gethead CRPIX1 stack1_${cam}.fits`; y0=`gethead CRPIX2 stack1_${cam}.fits`
    nx0=`gethead NAXIS1 stack1_${cam}.fits`; ny0=`gethead NAXIS2 stack1_${cam}.fits`
    function do_weights() {
        local file=$1
        local base=${file%'.fits'}
        local wfile=${base}.wt.fits
        local wmfile=${base}.wmap_mask.fits
        local r0=`gethead CRVAL1 $file`
        local d0=`gethead CRVAL2 $file`
        local x=`gethead CRPIX1 $file`
        local y=`gethead CRPIX2 $file`
        local dx=`echo $x | awk '{printf("%.0f\n",'$x0'-$1+1)}'`
        local dy=`echo $y | awk '{printf("%.0f\n",'$y0'-$1+1)}'`
        local x1=`gethead NAXIS1 $file | awk '{printf("%.0f\n",'$dx'+$1-1)}'`
        local y1=`gethead NAXIS2 $file | awk '{printf("%.0f\n",'$dy'+$1-1)}'`
        [ "$x1" -gt "$nx0" ] && {
            dx=`echo $dx | awk '{printf("%.0f\n",$1-'$x1'+'$nx0')}'`
            x1=$nx0
        }
        [ "$y1" -gt "$ny0" ] && {
            dy=`echo $dy | awk '{printf("%.0f\n",$1-'$y1'+'$ny0')}'`
            y1=$ny0
        }
        echo weight_clip $file $wfile $wmfile stack1_${cam}.fits[$dx:$x1,$dy:$y1] stack1_${cam}.wt.fits[$dx:$x1,$dy:$y1]
        weight_clip $file $wfile $wmfile stack1_${cam}.fits[$dx:$x1,$dy:$y1] stack1_${cam}.wt.fits[$dx:$x1,$dy:$y1]
        sethead CRPIX1=$x CRPIX2=$y CRVAL1=$r0 CRVAL2=$d0 $file
    }

    for file in `cat f$file_list`; do
        do_weights $file &
        gonogo
    done
    wait; go_iter=0

    # now produce all the weighted stacks
    iterstack_coatli.sh f$file_list gain=$gain
fi
