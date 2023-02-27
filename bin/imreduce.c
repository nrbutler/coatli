/*
  This file was downloaded from the CFITSIO utilities web page:
    http://heasarc.gsfc.nasa.gov/docs/software/fitsio/cexamples.html

  That page contains this text:
    You may freely modify, reuse, and redistribute these programs as you wish.

  We assume it was originally written by the CFITSIO authors (primarily William
  D. Pence).

  We (the Astrometry.net team) have modified it slightly.
  # Licensed under a 3-clause BSD style license - see LICENSE


*/

#include <string.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include "fitsio.h"

int main(int argc, char *argv[])
{
    fitsfile *afptr, *bfptr, *cfptr, *dfptr, *outfptr, *outfptrw;  /* FITS file pointers */
    unsigned long jj;
    int smt=0;  /* to invert or not, invert when smt=0*/
    int status = 0;  /* CFITSIO status value MUST be initialized to zero! */
    int anaxis, check = 1, ii, op, bitpix=-32;
    long npixels = 1, nrows = 1, firstpix[2] = {1,1}, lastpix[2] = {1,1};
    long firstpix1[2] = {1,1}, lastpix1[2] = {1,1};
    char extname[FLEN_VALUE], *extname1;
    char *strA,*strB;
    long anaxes[2] = {1,1};
    double *apix, *bpix, *cpix, *dpix, *opix, *wpix;
    double biaslevel=0.,gain=6.2, RN=10.,sigma2;
    double flat_min=0.,exptime=1.,mjd=0.,rm=RAND_MAX,rnum,sky;

    if (argc < 7) { 
      printf("Usage: imreduce datafile biasfile darkfile flatfile outfile outfile_wt <skylevel> <biaslevel> <smt> <RN> <gain>\n");
      printf("\n");
      printf("Just reduce an image\n");
      printf("\n");
      return(0);
    }

    fits_open_file(&afptr, argv[1], READONLY, &status); /* open input images */
    fits_open_file(&bfptr, argv[2], READONLY, &status);
    fits_open_file(&cfptr, argv[3], READONLY, &status);
    fits_open_file(&dfptr, argv[4], READONLY, &status);

    fits_get_img_dim(afptr, &anaxis, &status);  /* read dimensions */
    fits_get_img_size(afptr, 2, anaxes, &status);

    npixels = anaxes[0];  /* no. of pixels to read in each row */
    nrows = anaxes[1];

    if (status) {
       fits_report_error(stderr, status); /* print error message */
       return(status);
    }

    if (anaxis > 3) {
       printf("Error: images with > 3 dimensions are not supported\n");
       check = 0;
    }

    /* create the new empty output file if the above checks are OK */
    if (check && !fits_create_file(&outfptr, argv[5], &status) && !fits_create_file(&outfptrw, argv[6], &status))
    {
      /* copy all the header keywords from first image to new output file */
      fits_copy_header(afptr, outfptr, &status);
      fits_update_key(outfptr, TINT, "BITPIX", &bitpix, NULL, &status);
      fits_update_key(outfptr, TINT, "NAXIS1", &nrows, NULL, &status);
      fits_update_key(outfptr, TINT, "NAXIS2", &npixels, NULL, &status);
      fits_delete_key(outfptr, "BZERO", &status);
      if (status!=0) status=0;
      fits_delete_key(outfptr, "BSCALE", &status);
      if (status!=0) status=0;

      fits_copy_header(afptr, outfptrw, &status);
      fits_update_key(outfptrw, TINT, "BITPIX", &bitpix, NULL, &status);
      fits_update_key(outfptrw, TINT, "NAXIS1", &nrows, NULL, &status);
      fits_update_key(outfptrw, TINT, "NAXIS2", &npixels, NULL, &status);
      fits_delete_key(outfptrw, "BZERO", &status);
      if (status!=0) status=0;
      fits_delete_key(outfptrw, "BSCALE", &status);
      if (status!=0) status=0;

      fits_read_key(dfptr, TDOUBLE, "FLATMIN", &flat_min, NULL, &status);
      if (status!=0) {
          status=0;
          flat_min=0.;
      }
      fits_read_key(afptr, TDOUBLE, "EXPTIME", &exptime, NULL, &status);
      if (status!=0) {
          status=0;
          exptime=1.;
      }
      fits_read_key(afptr, TDOUBLE, "MJD", &mjd, NULL, &status);
      if (status!=0) {
          status=0;
          mjd=0.;
      }
      srand((unsigned long)(mjd*1.e6));
      fits_delete_key(outfptr, "DATASEC", &status);
      fits_delete_key(outfptr, "CCDSEC", &status);
      fits_delete_key(outfptr, "BIASSEC", &status);
      status=0;
      fits_delete_key(outfptrw, "DATASEC", &status);
      fits_delete_key(outfptrw, "CCDSEC", &status);
      fits_delete_key(outfptrw, "BIASSEC", &status);
      status=0;

      apix = (double *) malloc(npixels * sizeof(double)); /* mem for 1 row */
      bpix = (double *) malloc(npixels * sizeof(double));
      cpix = (double *) malloc(npixels * sizeof(double));
      dpix = (double *) malloc(npixels * sizeof(double));
      opix = (double *) malloc(npixels * nrows * sizeof(double));
      wpix = (double *) malloc(npixels * nrows * sizeof(double));

      if (apix == NULL || bpix == NULL || cpix == NULL || opix == NULL || wpix == NULL) {
        printf("Memory allocation error\n");
        return(1);
      }
      if (argc>7) sky=atof(argv[7]);
      if (argc>8) biaslevel=atof(argv[8]);
      if (argc>9) smt=atoi(argv[9]);
      if (argc>10) RN=atof(argv[10]);
      if (argc>11) gain=atof(argv[11]);

      sigma2 = (RN*RN/gain + fabs(sky))/(gain*exptime*exptime);

      /* loop over all rows of the plane */
      for (firstpix[1] = 1; firstpix[1] <= nrows; firstpix[1]++) {
        lastpix[1] = nrows - firstpix[1] + 1;
        /* Read both images as doubles, regardless of actual datatype.  */
        /* Give starting pixel coordinate and no. of pixels to read.    */
        /* This version does not support undefined pixels in the image. */

        if (fits_read_pix(afptr, TDOUBLE, firstpix, npixels, NULL, apix,
                          NULL, &status)  ||
            fits_read_pix(bfptr, TDOUBLE, firstpix, npixels,  NULL, bpix,
                          NULL, &status)  ||
            fits_read_pix(cfptr, TDOUBLE, firstpix, npixels,  NULL, cpix,
                          NULL, &status)  ||
            fits_read_pix(dfptr, TDOUBLE, firstpix, npixels,  NULL, dpix,
                          NULL, &status)  )
            break;   /* jump out of loop on error */

        for(ii=0; ii< npixels; ii++) {
          rnum = rand()/rm;
          if (smt==0) jj = lastpix[1]-1+nrows*(npixels-ii-1);
          else jj = firstpix[1]-1+nrows*ii;
          if (dpix[ii]>flat_min) {
              opix[jj] = (apix[ii]+rnum-bpix[ii]-cpix[ii]*exptime-biaslevel)/(exptime*dpix[ii]);
              //wpix[jj] = dpix[ii]/sigma2;
              wpix[jj] = 1./sigma2;
          }
          else wpix[jj]=opix[jj]=0;
        }

      }

      lastpix1[0]=nrows; lastpix1[1] = npixels;

      fits_write_subset(outfptr, TDOUBLE, firstpix1, lastpix1, opix, &status);
      fits_close_file(outfptr, &status);
      fits_write_subset(outfptrw, TDOUBLE, firstpix1, lastpix1, wpix, &status);
      fits_close_file(outfptrw, &status);

      free(apix);
      free(bpix);
      free(cpix);
      free(dpix);
      free(opix);
      free(wpix);
    }

    fits_close_file(afptr, &status);
    fits_close_file(bfptr, &status);
    fits_close_file(cfptr, &status);
    fits_close_file(dfptr, &status);

    if (status) fits_report_error(stderr, status); /* print any error message */
    return(status);
}
