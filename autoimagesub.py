#!/usr/bin/env python

'''autoimagesub.py - Waqas Bhatti (wbhatti@astro.princeton.edu) - 09/2016

This contains functions to run image subtraction photometry continuously.

TODO:

- functions for running imagesub steps on lists of reduced FITS
- functions that search for reference images
- functions that search for reference image photometry catalogs
- function that knows how to time-out a subprocess call to ficonv

'''

#############
## IMPORTS ##
#############

import os
import os.path
import glob
import multiprocessing as mp
import subprocess
from subprocess import check_output
import shlex
from datetime import datetime
import re
import json
import shutil
import random
import cPickle as pickle
import sqlite3
import time


import aperturephot as ap
import imagesubphot as ism
from imageutils import get_header_keyword_list


############
## CONFIG ##
############

DEBUG = False

# used to get the station ID, frame number, and CCD number from a FITS filename
FRAMEREGEX = re.compile(r'(\d{1})\-(\d{6}\w{0,1})_(\d{1})')

# this defines the field string and CCDs
FIELD_REGEX = re.compile('^G(\d{2})(\d{2})([\+\-]\d{2})(\d{2})_(\w{3})$')
FIELD_CCDS = [5,6,7,8]

# defines where the reference frames go
REFBASEDIR = '/P/HP0/BASE/reference-frames'
REFINFO = os.path.join(REFBASEDIR,'TM-refinfo.sqlite')


######################
## REFERENCE FRAMES ##
######################

def generate_astromref(fitsfiles,
                       makeactive=True,
                       field=None,
                       ccd=None,
                       projectid=None,
                       refdir=REFBASEDIR,
                       refinfo=REFINFO):
    '''This chooses an astrometry reference frame from the frames in fitfiles.

    writes the frame to refdir.

    ref frames have the following filename pattern:

    proj{projectid}-ccd{ccd}-{field}-astromref-{origfname}.fits

    if field, ccd, or projectid are None, these values are taken from the FITS
    file headers.

    updates the refinfo database.

    '''

    goodfits = [x for x in fitsfiles if os.path.exists(x)]

    if not goodfits:
        print('ERR! %sZ: no good FITS files found in input list' %
              (datetime.utcnow().isoformat(),))
        return

    # find the astromref
    astromref = ism.select_astromref_frame(
        fitsfiles,
        '1-*.fits',
    )

    # if an astromref was successfully found, then add its info to the DB
    if astromref:

        if field and ccd and projectid:

            frameinfo = {'field':field,
                         'ccd':ccd,
                         'projectid':projectid}

        else:

            # get the frame info
            frameelems = get_header_keyword_list(astromref['astromref'],
                                                 ['object',
                                                  'projid'])

            felems = FRAMEREGEX.findall(
                os.path.basename(astromref['astromref'])
            )

            if felems and felems[0]:

                ccd = felems[0][2]
                frameinfo = {'field':frameelems['object'],
                             'ccd':ccd,
                             'projectid':frameelems['projid']}

            else:

                print('ERR! %sZ: could not figure out CCD for astromref: %s' %
                      (datetime.utcnow().isoformat(), astromref['astromref']))
                return

            # now that we have the astromref frame, copy it over to the
            # system-wide reference-images directory along with its JPEG
            # snapshot
            areftargetfits = ('proj{projectid}-{field}-'
                              'ccd{ccd}-astromref-{origfname}.fits').format(
                                  projectid=frameinfo['projectid'],
                                  field=frameinfo['field'],
                                  ccd=frameinfo['ccd'],
                                  origfname=os.path.splitext(
                                      os.path.basename(astromref['astromref'])
                                  )[0]
                               )
            areftargetjpeg = areftargetfits.replace('.fits','.jpeg')

            shutil.copy(astromref['astromref'],os.path.join(REFBASEDIR,
                                                            areftargetfits))
            shutil.copy(astromref['framejpg'],os.path.join(REFBASEDIR,
                                                            areftargetjpeg))

            # now, put together the information and write to the refinfo sqlite

            query = ("insert into astromrefs "
                     "(field, projectid, ccd, isactive, unixtime, "
                     "framepath, jpegpath, sval, dval, bgv, ndet, "
                     "comment) values "
                     "(?, ?, ?, ?, ?, "
                     "?, ?, ?, ?, ?, ?, "
                     "?)")
            params = (frameinfo['field'],
                      frameinfo['projectid'],
                      frameinfo['ccd'],
                      1 if makeactive else 0,
                      time.time(),

                      os.path.join(REFBASEDIR,areftargetfits),
                      os.path.join(REFBASEDIR,areftargetjpeg),
                      astromref['sval'],
                      astromref['dval'],
                      astromref['bgv'],
                      astromref['ndet'],

                      (astromref['comment'] +
                       '; original: %s' % astromref['astromref']))

            db = sqlite3.connect(refinfo)
            cur = db.cursor()

            try:

                astromref.update(frameinfo)
                cur.execute(query, params)
                db.commit()

                print('%sZ: using astromref %s for '
                      'field %s, ccd %s, project id %s, database updated.' %
                      (datetime.utcnow().isoformat(),
                       astromref['astromref'],
                       astromref['field'],
                       astromref['ccd'],
                       astromref['projectid']))

                returnval = astromref

            except Exception as e:

                print('ERR! %sZ: could not update refinfo DB! error was: %s' %
                      (datetime.utcnow().isoformat(), e))
                returnval = None
                db.rollback()

            db.close()

    # otherwise, do nothing
    else:

        print('ERR! %sZ: could not find an astromref frame' %
              (datetime.utcnow().isoformat(),))
        returnval = None


    return returnval



def get_astromref(projectid, field, ccd, refinfo=REFINFO):
    '''This finds the reference frame for the field, projectid, and ccd
    combination using the TM-refinfo.sqlite database.


    '''

    db = sqlite3.connect(REFINFO)
    cur = db.cursor()

    query = ('select field, projectid, ccd, unixtime, '
             'framepath, jpegpath, sval, dval, bgv, ndet, comment '
             'from astromrefs where '
             'projectid = ? and field = ? and ccd = ? and '
             'isactive = 1')
    params = (projectid, field, ccd)

    try:

        cur.execute(query, params)
        rows = cur.fetchone()

        astromref = {x:y for (x,y) in zip(('field','projectid','ccd',
                                           'unixtime','framepath','jpegpath',
                                           'sval','dval','bgv',
                                           'ndet','comment'),rows)}

        returnval = astromref

    except Exception as e:

        print('ERR! %sZ: could not get astromref info '
              'from DB! error was: %s' %
              (datetime.utcnow().isoformat(), e))
        returnval = None

    db.close()

    return returnval
