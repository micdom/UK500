# ----
# Finally, load ``nco`` tools to tidy some grid scale issues
#'
#::

  # load nco modules. Modules do not currently exist on ARCHER2 so do elsewhere.
  module load nco

  # Remove weirdness with negative bathymetry and make minimum bathymetry
  # equal to 10 m (resolve any possible wet-drying problems)
  ncap2 -s 'where(Bathymetry < 0) Bathymetry=0' bathy_meter.nc tmp1.nc
  ncap2 -s 'where(Bathymetry < 10 && Bathymetry > 0) Bathymetry=10' tmp1.nc -O bathy_meter.nc
  rm tmp1.nc

  # Copy it if you want for safe keeping
  cp bathy_meter.nc bathy_meter_ORCA12.nc

  # Fix bathymetry to deal with instabilities (opening some straights that
  # have only 2 grid points)
  ncap2 -s 'Bathymetry(140,464)=200' bathy_meter_ORCA12.nc bathy_meter_ORCA12.nc -O
  ncap2 -s 'Bathymetry(141,464)=200' bathy_meter_ORCA12.nc bathy_meter_ORCA12.nc -O
  ncap2 -s 'Bathymetry(145,563)=400' bathy_meter_ORCA12.nc bathy_meter_ORCA12.nc -O
  ncap2 -s 'Bathymetry(145,564)=400' bathy_meter_ORCA12.nc bathy_meter_ORCA12.nc -O
  ncap2 -s 'Bathymetry(140,467)=80' bathy_meter_ORCA12.nc bathy_meter_ORCA12.nc -O

  cd $WDIR/SCRIPTS
