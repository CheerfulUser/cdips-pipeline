#!/usr/bin/env bash

##########################################
#
# USAGE:
#   ./reduce_ete6_field.sh &> logs/log1.txt &
#
# PURPOSE:
#   make lightcurves from images
#
##########################################

#
#
# data-specific parameters
projectid=43
orbit='orbit-10'

# reduction-specific parameters
tuneparameters=true
nworkers=20
aperturelist="1.95:7.0:6.0,2.45:7.0:6.0,2.95:7.0:6.0"
epdsmooth=11    # 11*30min = 5.5 hour median smooth in EPD pre-processing.
epdsigclip=10
photdisjointradius=2
anetfluxthreshold=50000
anettweak=6
anetradius=30
initccdextent="0:2048,0:2048"
kernelspec="b/4;i/4;d=4/4"
catalog_faintrmag=15.5
fistarfluxthreshold=1000
photreffluxthreshold=1000


###############################################################################
# define paths, make directories.

if [ "$tuneparameters" = true ] ; then
  tunefullstr='TUNE'
else
  tunefullstr='FULL'
fi

ix=0
for camnum in {4..1}; do
  for ccdnum in {3..1}; do

    # define paths
    LOCAL_IMGBASE="/nfs/phtess1/ar1/TESS/SIMFFI/RED_IMGSUB/"${tunefullstr}
    orbitdir=$LOCAL_IMGBASE"/"${orbit}"/"
    fitsdir=$orbitdir"RED_"${camnum}"-"${ccdnum}"_ISP/"
    LOCAL_GLOBPATTERN="tess?????????????-"${camnum}"-"${ccdnum}
    LOCAL_GLOBPATTERN+="-0016_cal_img.fits"
    fitsglob=$LOCAL_GLOBPATTERN
    lcbase="/nfs/phtess1/ar1/TESS/SIMFFI/LC/"${tunefullstr}
    lcorbit=$lcbase"/"${orbit}"/"
    lcdir=${lcorbit}"ISP_"${camnum}"-"${ccdnum}"/"

    # make directories
    if [ ! -d "$LOCAL_IMGBASE" ]; then
      mkdir $LOCAL_IMGBASE
    fi
    if [ ! -d "$orbitdir" ]; then
      mkdir $orbitdir
    fi
    if [ ! -d "$fitsdir" ]; then
      mkdir $fitsdir
    fi
    if [ ! -d "$lcbase" ]; then
      mkdir $lcbase
    fi
    if [ ! -d "$lcorbit" ]; then
      mkdir $lcorbit
    fi
    if [ ! -d "$lcdir" ]; then
      mkdir $lcdir
    fi

    logname=${orbit}'-cam'${camnum}'-ccd'${ccdnum}'.log'
    delaymin=$((30*ix))

    python TESS_ETE6_reduction.py \
      --projectid $projectid \
      --fitsdir $fitsdir --fitsglob $fitsglob --outdir $fitsdir --field $orbit\
      --nworkers $nworkers --aperturelist $aperturelist --lcdirectory $lcdir \
      --convert_to_fitsh_compatible --epdsmooth $epdsmooth \
      --epdsigclip $epdsigclip --photdisjointradius $photdisjointradius \
      --tuneparameters $tuneparameters --kernelspec $kernelspec \
      --anetfluxthreshold $anetfluxthreshold --anettweak $anettweak \
      --initccdextent $initccdextent --anetradius $anetradius \
      --delaymin $delaymin --catalog_faintrmag $catalog_faintrmag \
      --fistarfluxthreshold $fistarfluxthreshold \
      --photreffluxthreshold $photreffluxthreshold \
      &> logs/$logname &

    echo "launching reduction for "${fitsdir}" in "$delaymin" minutes"

    ix=$((ix + 1))

  done
done