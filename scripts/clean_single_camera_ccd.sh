#!/usr/bin/env bash

# PURPOSE: USE WITH CAUTION.
#
# remove post-presubtraction files:
#   (XTRNS, .itrans, .xysdk, astromref, rsub*, subtractedconv)
# remove select lightcurves
# remove select reference images
# clear out astromrefs and photrefs table.
# clear out calibratedframes table.
# clear frameinfo cache from past week. 
camnum=1
ccdnum=1
projectid=1548
sector='s0010'
tuneparameters=false

##########

psql -U hpx -h xphtess1 hpx -c \
  "delete from astromrefs where projectid = "${projectid}" and camera = "${camnum}" and ccd = "${ccdnum}";"

psql -U hpx -h xphtess1 hpx -c \
  "delete from photrefs where projectid = "${projectid}" and camera = "${camnum}" and ccd = "${ccdnum}";"

##########

# define paths to remove

if [ "$tuneparameters" = true ] ; then
  tunefullstr='TUNE'
else
  tunefullstr='FULL'
fi

# get paths
LOCAL_IMGBASE="/nfs/phtess2/ar0/TESS/FFI/RED_IMGSUB/"${tunefullstr}
sectordir=$LOCAL_IMGBASE"/"${sector}"/"
fitsdir=$sectordir"RED_"${camnum}"-"${ccdnum}"-"${projectid}"_ISP/"
LOCAL_GLOBPATTERN='tess?????????????-'${sector}'-'${camnum}'-'${ccdnum}'-'${scid}'_cal_img_bkgdsub.fits'
fitsglob=$LOCAL_GLOBPATTERN
lcbase="/nfs/phtess2/ar0/TESS/FFI/LC/"${tunefullstr}
lcsector=$lcbase"/"${sector}"/"
lcdir=${lcsector}"ISP_"${camnum}"-"${ccdnum}"-"${projectid}"/"
lcdirold=${lcsector}"ISP_"${camnum}"-"${ccdnum}"-"${projectid}"_old/"

echo "removing post-presubtraction files from "${fitsdir}

# from imagesubphot
rm ${fitsdir}*XTRNS*jpg
rm ${fitsdir}*xtrns.fits
rm ${fitsdir}*.itrans
rm ${fitsdir}*.xysdk
rm ${fitsdir}*ASTOMREF*jpg
rm ${fitsdir}rsub-*
rm ${fitsdir}JPEG-SUBTRACTEDCONV*jpg

# remove lightcurves and stats. this takes a while. first rename, then run!
echo "moving "${lcdir}" to "${lcdirold}
mv ${lcdir} ${lcdirold}
echo "removing lightcurves from "${lcdirold}
rm -rf ${lcdirold}

echo "removing all reference files"
rm /nfs/phtess2/ar0/TESS/FFI/BASE/reference-frames/*proj${projectid}-camera${camnum}-ccd${ccdnum}*

# remove frameinfo cache directory
fname=`find /nfs/phtess2/ar0/TESS/FFI/BASE/frameinfo-cache/*/*${sector}-${camnum}-${ccdnum}-${scid}*jpg | head -n1`
dname=`dirname $fname`

echo "removing frameinfo cache dir for "${fname}
rm -rf $dname

# clean calibratedframes. regex reference:
# https://www.postgresql.org/docs/9.5/static/functions-matching.html

psql -U hpx -h xphtess1 hpx -c \
  "DELETE from calibratedframes where fits like '"${fitsdir}"%';"
psql -U hpx -h xphtess1 hpx -c \
  "DELETE from calibratedframes where (fitsheader->'PROJID' ='"${projectid}"');"
