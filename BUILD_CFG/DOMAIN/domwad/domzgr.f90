MODULE domzgr
   !!==============================================================================
   !!                       ***  MODULE domzgr   ***
   !! Ocean domain : definition of the vertical coordinate system
   !!==============================================================================
   !! History :  OPA  ! 1995-12  (G. Madec)  Original code : s vertical coordinate
   !!                 ! 1997-07  (G. Madec)  lbc_lnk call
   !!                 ! 1997-04  (J.-O. Beismann) 
   !!            8.5  ! 2002-09  (A. Bozec, G. Madec)  F90: Free form and module
   !!             -   ! 2002-09  (A. de Miranda)  rigid-lid + islands
   !!  NEMO      1.0  ! 2003-08  (G. Madec)  F90: Free form and module
   !!             -   ! 2005-10  (A. Beckmann)  modifications for hybrid s-ccordinates & new stretching function
   !!            2.0  ! 2006-04  (R. Benshila, G. Madec)  add zgr_zco
   !!            3.0  ! 2008-06  (G. Madec)  insertion of domzgr_zps.h90 & conding style
   !!            3.2  ! 2009-07  (R. Benshila) Suppression of rigid-lid option
   !!            3.3  ! 2010-11  (G. Madec) add mbk. arrays associated to the deepest ocean level
   !!            3.4  ! 2012-08  (J. Siddorn) added Siddorn and Furner stretching function
   !!            3.4  ! 2012-12  (R. Bourdalle-Badie and G. Reffray)  modify C1D case  
   !!            3.6  ! 2014-11  (P. Mathiot and C. Harris) add ice shelf capabilitye  
   !!            3.?  ! 2015-11  (H. Liu) Modifications for Wetting/Drying
   !!----------------------------------------------------------------------

   !!----------------------------------------------------------------------
   !!   dom_zgr          : defined the ocean vertical coordinate system
   !!       zgr_bat      : bathymetry fields (levels and meters)
   !!       zgr_bat_zoom : modify the bathymetry field if zoom domain
   !!       zgr_bat_ctl  : check the bathymetry files
   !!       zgr_bot_level: deepest ocean level for t-, u, and v-points
   !!       zgr_z        : reference z-coordinate 
   !!       zgr_zco      : z-coordinate 
   !!       zgr_zps      : z-coordinate with partial steps
   !!       zgr_sco      : s-coordinate
   !!       fssig        : tanh stretch function
   !!       fssig1       : Song and Haidvogel 1994 stretch function
   !!       fgamma       : Siddorn and Furner 2012 stretching function
   !!---------------------------------------------------------------------
   USE oce               ! ocean variables
   USE dom_oce           ! ocean domain
   USE closea            ! closed seas
   !
   USE in_out_manager    ! I/O manager
   USE iom               ! I/O library
   USE lbclnk            ! ocean lateral boundary conditions (or mpp link)
   USE lib_mpp           ! distributed memory computing library
   USE wrk_nemo          ! Memory allocation
   USE timing            ! Timing
   USE zgrmes            ! MES

   IMPLICIT NONE
   PRIVATE

   PUBLIC   dom_zgr        ! called by dom_init.F90

   !                              !!* Namelist namzgr_sco *
   LOGICAL  ::   ln_s_sh94         ! use hybrid s-sig Song and Haidvogel 1994 stretching function fssig1 (ln_sco=T)
   LOGICAL  ::   ln_s_sf12         ! use hybrid s-z-sig Siddorn and Furner 2012 stretching function fgamma (ln_sco=T)
   !
   REAL(wp) ::   rn_sbot_min       ! minimum depth of s-bottom surface (>0) (m)
   REAL(wp) ::   rn_sbot_max       ! maximum depth of s-bottom surface (= ocean depth) (>0) (m)
   REAL(wp) ::   rn_rmax           ! maximum cut-off r-value allowed (0<rn_rmax<1)
   REAL(wp) ::   rn_hc             ! Critical depth for transition from sigma to stretched coordinates
   ! Song and Haidvogel 1994 stretching parameters
   REAL(wp) ::   rn_theta          ! surface control parameter (0<=rn_theta<=20)
   REAL(wp) ::   rn_thetb          ! bottom control parameter  (0<=rn_thetb<= 1)
   REAL(wp) ::   rn_bb             ! stretching parameter 
   !                                        ! ( rn_bb=0; top only, rn_bb =1; top and bottom)
   ! Siddorn and Furner stretching parameters
   LOGICAL  ::   ln_sigcrit        ! use sigma coordinates below critical depth (T) or Z coordinates (F) for Siddorn & Furner stretch 
   REAL(wp) ::   rn_alpha          ! control parameter ( > 1 stretch towards surface, < 1 towards seabed)
   REAL(wp) ::   rn_efold          !  efold length scale for transition to stretched coord
   REAL(wp) ::   rn_zs             !  depth of surface grid box
                           !  bottom cell depth (Zb) is a linear function of water depth Zb = H*a + b
   REAL(wp) ::   rn_zb_a           !  bathymetry scaling factor for calculating Zb
   REAL(wp) ::   rn_zb_b           !  offset for calculating Zb

  !! * Substitutions
   !!----------------------------------------------------------------------
   !!                   ***  vectopt_loop_substitute  ***
   !!----------------------------------------------------------------------
   !! ** purpose :   substitute the inner loop start/end indices with CPP macro
   !!                allow unrolling of do-loop (useful with vector processors)
   !!----------------------------------------------------------------------
   !!----------------------------------------------------------------------
   !! NEMO/OPA 3.7 , NEMO Consortium (2014)
   !! $Id: vectopt_loop_substitute.h90 4990 2014-12-15 16:42:49Z timgraham $ 
   !! Software governed by the CeCILL licence (./LICENSE)
   !!----------------------------------------------------------------------
   !!----------------------------------------------------------------------
   !! NEMO/OPA 3.3.1 , NEMO Consortium (2011)
   !! $Id: domzgr.F90 6827 2016-08-01 13:37:15Z flavoni $
   !! Software governed by the CeCILL licence     (./LICENSE)
   !!----------------------------------------------------------------------
CONTAINS       

   SUBROUTINE dom_zgr
      !!----------------------------------------------------------------------
      !!                ***  ROUTINE dom_zgr  ***
      !!                   
      !! ** Purpose :   set the depth of model levels and the resulting 
      !!              vertical scale factors.
      !!
      !! ** Method  : - reference 1D vertical coordinate (gdep._1d, e3._1d)
      !!              - read/set ocean depth and ocean levels (bathy, mbathy)
      !!              - vertical coordinate (gdep., e3.) depending on the 
      !!                coordinate chosen :
      !!                   ln_zco=T   z-coordinate   
      !!                   ln_zps=T   z-coordinate with partial steps
      !!                   ln_zco=T   s-coordinate 
      !!
      !! ** Action  :   define gdep., e3., mbathy and bathy
      !!----------------------------------------------------------------------
      INTEGER ::   ioptio, ibat   ! local integer
      INTEGER ::   ios
      !
      NAMELIST/namzgr/ ln_zco, ln_zps, ln_sco, ln_mes, ln_isfcav, ln_linssh
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )   CALL timing_start('dom_zgr')
      !
      REWIND( numnam_ref )              ! Namelist namzgr in reference namelist : Vertical coordinate
      READ  ( numnam_ref, namzgr, IOSTAT = ios, ERR = 901 )
901   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namzgr in reference namelist', lwp )

      REWIND( numnam_cfg )              ! Namelist namzgr in configuration namelist : Vertical coordinate
      READ  ( numnam_cfg, namzgr, IOSTAT = ios, ERR = 902 )
902   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namzgr in configuration namelist', lwp )
      IF(lwm) WRITE ( numond, namzgr )

      IF(lwp) THEN                     ! Control print
         WRITE(numout,*)
         WRITE(numout,*) 'dom_zgr : vertical coordinate'
         WRITE(numout,*) '~~~~~~~'
         WRITE(numout,*) '   Namelist namzgr : set vertical coordinate'
         WRITE(numout,*) '      z-coordinate - full steps      ln_zco    = ', ln_zco
         WRITE(numout,*) '      z-coordinate - partial steps   ln_zps    = ', ln_zps
         WRITE(numout,*) '      s- or hybrid z-s-coordinate    ln_sco    = ', ln_sco
         WRITE(numout,*) '      MES-coordinate                 ln_mes    = ', ln_mes
         WRITE(numout,*) '      ice shelf cavities             ln_isfcav = ', ln_isfcav
         WRITE(numout,*) '      linear free surface            ln_linssh = ', ln_linssh
      ENDIF

      IF( ln_linssh .AND. lwp) WRITE(numout,*) '   linear free surface: the vertical mesh does not change in time'

      ioptio = 0                       ! Check Vertical coordinate options
      IF( ln_zco      )   ioptio = ioptio + 1
      IF( ln_zps      )   ioptio = ioptio + 1
      IF( ln_sco      )   ioptio = ioptio + 1
      IF( ln_mes      )   ioptio = ioptio + 1
      IF( ioptio /= 1 )   CALL ctl_stop( ' none or several vertical coordinate options used' )
      !
      ioptio = 0
      IF ( ln_zco .AND. ln_isfcav ) ioptio = ioptio + 1
      IF ( ln_sco .AND. ln_isfcav ) ioptio = ioptio + 1
      IF( ioptio > 0 )   CALL ctl_stop( ' Cavity not tested/compatible with full step (zco) and sigma (ln_sco) ' )
      !
      ! Build the vertical coordinate system
      ! ------------------------------------
                          CALL zgr_z            ! Reference z-coordinate system (always called)
                          CALL zgr_bat          ! Bathymetry fields (levels and meters)
      IF( ln_zco      )   CALL zgr_zco          ! z-coordinate
      IF( ln_zps      )   CALL zgr_zps          ! Partial step z-coordinate
      IF( ln_sco      )   CALL zgr_sco          ! s-coordinate or hybrid z-s coordinate
      IF( ln_mes      )   CALL zgr_mes          ! MES-coordinate
      !
      ! final adjustment of mbathy & check 
      ! -----------------------------------
      IF( lzoom       )   CALL zgr_bat_zoom     ! correct mbathy in case of zoom subdomain
                          CALL zgr_bat_ctl      ! check bathymetry (mbathy) and suppress isolated ocean points
                          CALL zgr_bot_level    ! deepest ocean level for t-, u- and v-points
                          CALL zgr_top_level    ! shallowest ocean level for T-, U-, V- points
      !
      IF( nprint == 1 .AND. lwp )   THEN
         WRITE(numout,*) ' MIN val mbathy  ', MINVAL(  mbathy(:,:) ), ' MAX ', MAXVAL( mbathy(:,:) )
         WRITE(numout,*) ' MIN val depth t ', MINVAL( gdept_0(:,:,:) ),   &
            &                          ' w ', MINVAL( gdepw_0(:,:,:) ), '3w ', MINVAL( gde3w_0(:,:,:) )
         WRITE(numout,*) ' MIN val e3    t ', MINVAL(   e3t_0(:,:,:) ), ' f ', MINVAL(   e3f_0(:,:,:) ),  &
            &                          ' u ', MINVAL(   e3u_0(:,:,:) ), ' u ', MINVAL(   e3v_0(:,:,:) ),  &
            &                          ' uw', MINVAL(  e3uw_0(:,:,:) ), ' vw', MINVAL(  e3vw_0(:,:,:)),   &
            &                          ' w ', MINVAL(   e3w_0(:,:,:) )

         WRITE(numout,*) ' MAX val depth t ', MAXVAL( gdept_0(:,:,:) ),   &
            &                          ' w ', MAXVAL( gdepw_0(:,:,:) ), '3w ', MAXVAL( gde3w_0(:,:,:) )
         WRITE(numout,*) ' MAX val e3    t ', MAXVAL(   e3t_0(:,:,:) ), ' f ', MAXVAL(   e3f_0(:,:,:) ),  &
            &                          ' u ', MAXVAL(   e3u_0(:,:,:) ), ' u ', MAXVAL(   e3v_0(:,:,:) ),  &
            &                          ' uw', MAXVAL(  e3uw_0(:,:,:) ), ' vw', MAXVAL(  e3vw_0(:,:,:) ),  &
            &                          ' w ', MAXVAL(   e3w_0(:,:,:) )
      ENDIF
      !
      IF( nn_timing == 1 )  CALL timing_stop('dom_zgr')
      !
   END SUBROUTINE dom_zgr


   SUBROUTINE zgr_z
      !!----------------------------------------------------------------------
      !!                   ***  ROUTINE zgr_z  ***
      !!                   
      !! ** Purpose :   set the depth of model levels and the resulting 
      !!      vertical scale factors.
      !!
      !! ** Method  :   z-coordinate system (use in all type of coordinate)
      !!        The depth of model levels is defined from an analytical
      !!      function the derivative of which gives the scale factors.
      !!        both depth and scale factors only depend on k (1d arrays).
      !!              w-level: gdepw_1d  = gdep(k)
      !!                       e3w_1d(k) = dk(gdep)(k)     = e3(k)
      !!              t-level: gdept_1d  = gdep(k+0.5)
      !!                       e3t_1d(k) = dk(gdep)(k+0.5) = e3(k+0.5)
      !!
      !! ** Action  : - gdept_1d, gdepw_1d : depth of T- and W-point (m)
      !!              - e3t_1d  , e3w_1d   : scale factors at T- and W-levels (m)
      !!
      !! Reference : Marti, Madec & Delecluse, 1992, JGR, 97, No8, 12,763-12,766.
      !!----------------------------------------------------------------------
      INTEGER  ::   jk                     ! dummy loop indices
      REAL(wp) ::   zt, zw                 ! temporary scalars
      REAL(wp) ::   zsur, za0, za1, zkth   ! Values set from parameters in
      REAL(wp) ::   zacr, zdzmin, zhmax    ! par_CONFIG_Rxx.h90
      REAL(wp) ::   zrefdep                ! depth of the reference level (~10m)
      REAL(wp) ::   za2, zkth2, zacr2      ! Values for optional double tanh function set from parameters 
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_z')
      !
      ! Set variables from parameters
      ! ------------------------------
       zkth = ppkth       ;   zacr = ppacr
       zdzmin = ppdzmin   ;   zhmax = pphmax
       zkth2 = ppkth2     ;   zacr2 = ppacr2   ! optional (ldbletanh=T) double tanh parameters

      ! If ppa1 and ppa0 and ppsur are et to pp_to_be_computed
      !  za0, za1, zsur are computed from ppdzmin , pphmax, ppkth, ppacr
      IF(   ppa1  == pp_to_be_computed  .AND.  &
         &  ppa0  == pp_to_be_computed  .AND.  &
         &  ppsur == pp_to_be_computed           ) THEN
         !
         za1  = (  ppdzmin - pphmax / FLOAT(jpkm1)  )                                                      &
            & / ( TANH((1-ppkth)/ppacr) - ppacr/FLOAT(jpk-1) * (  LOG( COSH( (jpk - ppkth) / ppacr) )      &
            &                                                   - LOG( COSH( ( 1  - ppkth) / ppacr) )  )  )
         za0  = ppdzmin - za1 *              TANH( (1-ppkth) / ppacr )
         zsur =   - za0 - za1 * ppacr * LOG( COSH( (1-ppkth) / ppacr )  )
      ELSE
         za1 = ppa1 ;       za0 = ppa0 ;          zsur = ppsur
         za2 = ppa2                            ! optional (ldbletanh=T) double tanh parameter
      ENDIF

      IF(lwp) THEN                         ! Parameter print
         WRITE(numout,*)
         WRITE(numout,*) '    zgr_z   : Reference vertical z-coordinates'
         WRITE(numout,*) '    ~~~~~~~'
         IF(  ppkth == 0._wp ) THEN              
              WRITE(numout,*) '            Uniform grid with ',jpk-1,' layers'
              WRITE(numout,*) '            Total depth    :', zhmax
              WRITE(numout,*) '            Layer thickness:', zhmax/(jpk-1)
         ELSE
            IF( ppa1 == 0._wp .AND. ppa0 == 0._wp .AND. ppsur == 0._wp ) THEN
               WRITE(numout,*) '         zsur, za0, za1 computed from '
               WRITE(numout,*) '                 zdzmin = ', zdzmin
               WRITE(numout,*) '                 zhmax  = ', zhmax
            ENDIF
            WRITE(numout,*) '           Value of coefficients for vertical mesh:'
            WRITE(numout,*) '                 zsur = ', zsur
            WRITE(numout,*) '                 za0  = ', za0
            WRITE(numout,*) '                 za1  = ', za1
            WRITE(numout,*) '                 zkth = ', zkth
            WRITE(numout,*) '                 zacr = ', zacr
            IF( ldbletanh ) THEN
               WRITE(numout,*) ' (Double tanh    za2  = ', za2
               WRITE(numout,*) '  parameters)    zkth2= ', zkth2
               WRITE(numout,*) '                 zacr2= ', zacr2
            ENDIF
         ENDIF
      ENDIF


      ! Reference z-coordinate (depth - scale factor at T- and W-points)
      ! ======================
      IF( ppkth == 0._wp ) THEN            !  uniform vertical grid 



         za1 = zhmax / FLOAT(jpk-1) 

         DO jk = 1, jpk
            zw = FLOAT( jk )
            zt = FLOAT( jk ) + 0.5_wp
            gdepw_1d(jk) = ( zw - 1 ) * za1
            gdept_1d(jk) = ( zt - 1 ) * za1
            e3w_1d  (jk) =  za1
            e3t_1d  (jk) =  za1
         END DO
      ELSE                                ! Madec & Imbard 1996 function
         IF( .NOT. ldbletanh ) THEN
            DO jk = 1, jpk
               zw = REAL( jk , wp )
               zt = REAL( jk , wp ) + 0.5_wp
               gdepw_1d(jk) = ( zsur + za0 * zw + za1 * zacr * LOG ( COSH( (zw-zkth) / zacr ) )  )
               gdept_1d(jk) = ( zsur + za0 * zt + za1 * zacr * LOG ( COSH( (zt-zkth) / zacr ) )  )
               e3w_1d  (jk) =          za0      + za1        * TANH(       (zw-zkth) / zacr   )
               e3t_1d  (jk) =          za0      + za1        * TANH(       (zt-zkth) / zacr   )
            END DO
         ELSE
            DO jk = 1, jpk
               zw = FLOAT( jk )
               zt = FLOAT( jk ) + 0.5_wp
               ! Double tanh function
               gdepw_1d(jk) = ( zsur + za0 * zw + za1 * zacr * LOG ( COSH( (zw-zkth ) / zacr  ) )    &
                  &                             + za2 * zacr2* LOG ( COSH( (zw-zkth2) / zacr2 ) )  )
               gdept_1d(jk) = ( zsur + za0 * zt + za1 * zacr * LOG ( COSH( (zt-zkth ) / zacr  ) )    &
                  &                             + za2 * zacr2* LOG ( COSH( (zt-zkth2) / zacr2 ) )  )
               e3w_1d  (jk) =          za0      + za1        * TANH(       (zw-zkth ) / zacr  )      &
                  &                             + za2        * TANH(       (zw-zkth2) / zacr2 )
               e3t_1d  (jk) =          za0      + za1        * TANH(       (zt-zkth ) / zacr  )      &
                  &                             + za2        * TANH(       (zt-zkth2) / zacr2 )
            END DO
         ENDIF
         gdepw_1d(1) = 0._wp                    ! force first w-level to be exactly at zero
      ENDIF

      IF ( ln_isfcav .OR. ln_e3_dep ) THEN      ! e3. = dk[gdep]   
         !
!==>>>   need to be like this to compute the pressure gradient with ISF. 
!        If not, level beneath the ISF are not aligned (sum(e3t) /= depth)
!        define e3t_0 and e3w_0 as the differences between gdept and gdepw respectively
!
         DO jk = 1, jpkm1
            e3t_1d(jk) = gdepw_1d(jk+1)-gdepw_1d(jk) 
         END DO
         e3t_1d(jpk) = e3t_1d(jpk-1)   ! we don't care because this level is masked in NEMO

         DO jk = 2, jpk
            e3w_1d(jk) = gdept_1d(jk) - gdept_1d(jk-1) 
         END DO
         e3w_1d(1  ) = 2._wp * (gdept_1d(1) - gdepw_1d(1)) 
      END IF

!!gm BUG in s-coordinate this does not work!
      ! deepest/shallowest W level Above/Below ~10m
      zrefdep = 10._wp - 0.1_wp * MINVAL( e3w_1d )                   ! ref. depth with tolerance (10% of minimum layer thickness)
      nlb10 = MINLOC( gdepw_1d, mask = gdepw_1d > zrefdep, dim = 1 ) ! shallowest W level Below ~10m
      nla10 = nlb10 - 1                                              ! deepest    W level Above ~10m
!!gm end bug

      IF(lwp) THEN                        ! control print
         WRITE(numout,*)
         WRITE(numout,*) '              Reference z-coordinate depth and scale factors:'
         WRITE(numout, "(9x,' level  gdept_1d  gdepw_1d  e3t_1d   e3w_1d  ')" )
         WRITE(numout, "(10x, i4, 4f9.2)" ) ( jk, gdept_1d(jk), gdepw_1d(jk), e3t_1d(jk), e3w_1d(jk), jk = 1, jpk )
      ENDIF
      DO jk = 1, jpk                      ! control positivity
         IF( e3w_1d  (jk) <= 0._wp .OR. e3t_1d  (jk) <= 0._wp )   CALL ctl_stop( 'dom:zgr_z: e3w_1d or e3t_1d =< 0 '    )
         IF( gdepw_1d(jk) <  0._wp .OR. gdept_1d(jk) <  0._wp )   CALL ctl_stop( 'dom:zgr_z: gdepw_1d or gdept_1d < 0 ' )
      END DO
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_z')
      !
   END SUBROUTINE zgr_z


   SUBROUTINE zgr_bat
      !!----------------------------------------------------------------------
      !!                    ***  ROUTINE zgr_bat  ***
      !! 
      !! ** Purpose :   set bathymetry both in levels and meters
      !!
      !! ** Method  :   read or define mbathy and bathy arrays
      !!       * level bathymetry:
      !!      The ocean basin geometry is given by a two-dimensional array,
      !!      mbathy, which is defined as follow :
      !!            mbathy(ji,jj) = 1, ..., jpk-1, the number of ocean level
      !!                              at t-point (ji,jj).
      !!                            = 0  over the continental t-point.
      !!      The array mbathy is checked to verified its consistency with
      !!      model option. in particular:
      !!            mbathy must have at least 1 land grid-points (mbathy<=0)
      !!                  along closed boundary.
      !!            mbathy must be cyclic IF jperio=1.
      !!            mbathy must be lower or equal to jpk-1.
      !!            isolated ocean grid points are suppressed from mbathy
      !!                  since they are only connected to remaining
      !!                  ocean through vertical diffusion.
      !!      ntopo=-1 :   rectangular channel or bassin with a bump 
      !!      ntopo= 0 :   flat rectangular channel or basin 
      !!      ntopo= 1 :   mbathy is read in 'bathy_level.nc' NetCDF file
      !!                   bathy  is read in 'bathy_meter.nc' NetCDF file
      !!
      !! ** Action  : - mbathy: level bathymetry (in level index)
      !!              - bathy : meter bathymetry (in meters)
      !!----------------------------------------------------------------------
      INTEGER  ::   ji, jj, jk            ! dummy loop indices
      INTEGER  ::   inum                      ! temporary logical unit
      INTEGER  ::   ierror                    ! error flag
      INTEGER  ::   ii_bump, ij_bump, ih      ! bump center position
      INTEGER  ::   ii0, ii1, ij0, ij1, ik    ! local indices
      REAL(wp) ::   r_bump , h_bump , h_oce   ! bump characteristics 
      REAL(wp) ::   zi, zj, zh, zhmin         ! local scalars
      INTEGER , ALLOCATABLE, DIMENSION(:,:) ::   idta   ! global domain integer data
      REAL(wp), ALLOCATABLE, DIMENSION(:,:) ::   zdta   ! global domain scalar data
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_bat')
      !
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*) '    zgr_bat : defines level and meter bathymetry'
      IF(lwp) WRITE(numout,*) '    ~~~~~~~'
      !                                               ! ================== ! 
      IF( ntopo == 0 .OR. ntopo == -1 ) THEN          !   defined by hand  !
         !                                            ! ================== !
         !                                            ! global domain level and meter bathymetry (idta,zdta)
         !
         ALLOCATE( idta(jpidta,jpjdta), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'zgr_bat: unable to allocate idta array' )
         ALLOCATE( zdta(jpidta,jpjdta), STAT=ierror )
         IF( ierror > 0 )   CALL ctl_stop( 'STOP', 'zgr_bat: unable to allocate zdta array' )
         !
         IF( ntopo == 0 ) THEN                        ! flat basin
            IF(lwp) WRITE(numout,*)
            IF(lwp) WRITE(numout,*) '         bathymetry field: flat basin'
            IF( rn_bathy > 0.01 ) THEN 
               IF(lwp) WRITE(numout,*) '         Depth = rn_bathy read in namelist'
               zdta(:,:) = rn_bathy
               IF( ln_sco ) THEN                                   ! s-coordinate (zsc       ): idta()=jpk
                  idta(:,:) = jpkm1
               ELSE                                                ! z-coordinate (zco or zps): step-like topography
                  idta(:,:) = jpkm1
                  DO jk = 1, jpkm1
                     WHERE( gdept_1d(jk) < zdta(:,:) .AND. zdta(:,:) <= gdept_1d(jk+1) )   idta(:,:) = jk
                  END DO
               ENDIF
            ELSE
               IF(lwp) WRITE(numout,*) '         Depth = depthw(jpkm1)'
               idta(:,:) = jpkm1                            ! before last level
               zdta(:,:) = gdepw_1d(jpk)                     ! last w-point depth
               h_oce     = gdepw_1d(jpk)
            ENDIF
         ELSE                                         ! bump centered in the basin
            IF(lwp) WRITE(numout,*)
            IF(lwp) WRITE(numout,*) '         bathymetry field: flat basin with a bump'
            ii_bump = jpidta / 2                           ! i-index of the bump center
            ij_bump = jpjdta / 2                           ! j-index of the bump center
            r_bump  = 50000._wp                            ! bump radius (meters)       
            h_bump  =  2700._wp                            ! bump height (meters)
            h_oce   = gdepw_1d(jpk)                        ! background ocean depth (meters)
            IF(lwp) WRITE(numout,*) '            bump characteristics: '
            IF(lwp) WRITE(numout,*) '               bump center (i,j)   = ', ii_bump, ii_bump
            IF(lwp) WRITE(numout,*) '               bump height         = ', h_bump , ' meters'
            IF(lwp) WRITE(numout,*) '               bump radius         = ', r_bump , ' index'
            IF(lwp) WRITE(numout,*) '            background ocean depth = ', h_oce  , ' meters'
            !                                        
            DO jj = 1, jpjdta                              ! zdta :
               DO ji = 1, jpidta
                  zi = FLOAT( ji - ii_bump ) * ppe1_m / r_bump
                  zj = FLOAT( jj - ij_bump ) * ppe2_m / r_bump
                  zdta(ji,jj) = h_oce - h_bump * EXP( -( zi*zi + zj*zj ) )
               END DO
            END DO
            !                                              ! idta :
            IF( ln_sco ) THEN                                   ! s-coordinate (zsc       ): idta()=jpk
               idta(:,:) = jpkm1
            ELSE                                                ! z-coordinate (zco or zps): step-like topography
               idta(:,:) = jpkm1
               DO jk = 1, jpkm1
                  WHERE( gdept_1d(jk) < zdta(:,:) .AND. zdta(:,:) <= gdept_1d(jk+1) )   idta(:,:) = jk
               END DO
            ENDIF
         ENDIF
         !                                            ! set GLOBAL boundary conditions 
         !                                            ! Caution : idta on the global domain: use of jperio, not nperio
         IF( jperio == 1 .OR. jperio == 4 .OR. jperio == 6 ) THEN
            idta( :    , 1    ) = -1                ;      zdta( :    , 1    ) = -1._wp
            idta( :    ,jpjdta) =  0                ;      zdta( :    ,jpjdta) =  0._wp
         ELSEIF( jperio == 2 ) THEN
            idta( :    , 1    ) = idta( : ,  3  )   ;      zdta( :    , 1    ) = zdta( : ,  3  )
            idta( :    ,jpjdta) = 0                 ;      zdta( :    ,jpjdta) =  0._wp
            idta( 1    , :    ) = 0                 ;      zdta( 1    , :    ) =  0._wp
            idta(jpidta, :    ) = 0                 ;      zdta(jpidta, :    ) =  0._wp
         ELSE
            ih = 0                                  ;      zh = 0._wp
            IF( ln_sco )   ih = jpkm1               ;      IF( ln_sco )   zh = h_oce
            idta( :    , 1    ) = ih                ;      zdta( :    , 1    ) =  zh
            idta( :    ,jpjdta) = ih                ;      zdta( :    ,jpjdta) =  zh
            idta( 1    , :    ) = ih                ;      zdta( 1    , :    ) =  zh
            idta(jpidta, :    ) = ih                ;      zdta(jpidta, :    ) =  zh
         ENDIF

         !                                            ! local domain level and meter bathymetries (mbathy,bathy)
         mbathy(:,:) = 0                                   ! set to zero extra halo points
         bathy (:,:) = 0._wp                               ! (require for mpp case)
         DO jj = 1, nlcj                                   ! interior values
            DO ji = 1, nlci
               mbathy(ji,jj) = idta( mig(ji), mjg(jj) )
               bathy (ji,jj) = zdta( mig(ji), mjg(jj) )
            END DO
         END DO
         risfdep(:,:)=0.e0
         misfdep(:,:)=1
         !
         ! (ISF) TODO build ice draft netcdf file for isomip and build the corresponding part of code
         IF( cp_cfg == "isomip" .AND. ln_isfcav ) THEN 
            risfdep(:,:)=200.e0 
            misfdep(:,:)=1 
            ij0 = 1 ; ij1 = 40 
            DO jj = mj0(ij0), mj1(ij1) 
               risfdep(:,jj)=700.0_wp-(gphit(:,jj)+80.0_wp)*125.0_wp 
            END DO 
            WHERE( bathy(:,:) <= 0._wp )  risfdep(:,:) = 0._wp 
         ! 
         ELSEIF ( cp_cfg == "isomip2" .AND. ln_isfcav ) THEN
         ! 
            risfdep(:,:)=0.e0
            misfdep(:,:)=1
            ij0 = 1 ; ij1 = 40
            DO jj = mj0(ij0), mj1(ij1)
               risfdep(:,jj)=700.0_wp-(gphit(:,jj)+80.0_wp)*125.0_wp
            END DO
            WHERE( bathy(:,:) <= 0._wp )  risfdep(:,:) = 0._wp
         END IF
         !
         DEALLOCATE( idta, zdta )
         !
         !                                            ! ================ !
      ELSEIF( ntopo == 1 ) THEN                       !   read in file   ! (over the local domain)
         !                                            ! ================ !
         !
         IF( ln_zco )   THEN                          ! zco : read level bathymetry 
            CALL iom_open ( 'bathy_level.nc', inum )  
            CALL iom_get  ( inum, jpdom_data, 'Bathy_level', bathy )
            CALL iom_close( inum )
            mbathy(:,:) = INT( bathy(:,:) )
            ! initialisation isf variables
            risfdep(:,:)=0._wp ; misfdep(:,:)=1             
            !                                                ! =====================
            IF( cp_cfg == "orca" .AND. jp_cfg == 2 ) THEN    ! ORCA R2 configuration
               !                                             ! =====================
               !
               ii0 = 140   ;   ii1 = 140                  ! Gibraltar Strait open 
               ij0 = 102   ;   ij1 = 102                  ! (Thomson, Ocean Modelling, 1995)
               DO ji = mi0(ii0), mi1(ii1)
                  DO jj = mj0(ij0), mj1(ij1)
                     mbathy(ji,jj) = 15
                  END DO
               END DO
               IF(lwp) WRITE(numout,*)
               IF(lwp) WRITE(numout,*) '      orca_r2: Gibraltar strait open at i=',ii0,' j=',ij0
               !
               ii0 = 160   ;   ii1 = 160                  ! Bab el mandeb Strait open
               ij0 = 88    ;   ij1 = 88                   ! (Thomson, Ocean Modelling, 1995)
               DO ji = mi0(ii0), mi1(ii1)
                  DO jj = mj0(ij0), mj1(ij1)
                     mbathy(ji,jj) = 12
                  END DO
               END DO
               IF(lwp) WRITE(numout,*)
               IF(lwp) WRITE(numout,*) '      orca_r2: Bab el Mandeb strait open at i=',ii0,' j=',ij0
               !
            ENDIF
            !
         ENDIF
         IF( ln_zps .OR. ln_sco )   THEN              ! zps or sco : read meter bathymetry
            CALL iom_open ( 'bathy_meter.nc', inum ) 
            IF ( ln_isfcav ) THEN
               CALL iom_get  ( inum, jpdom_data, 'Bathymetry_isf', bathy, lrowattr=.false. )
            ELSE
               CALL iom_get  ( inum, jpdom_data, 'Bathymetry'    , bathy, lrowattr=ln_use_jattr  )
            END IF
            CALL iom_close( inum )
            !                                                
            ! initialisation isf variables
            risfdep(:,:)=0._wp ; misfdep(:,:)=1             
            !
            IF ( ln_isfcav ) THEN
               CALL iom_open ( 'isf_draft_meter.nc', inum ) 
               CALL iom_get  ( inum, jpdom_data, 'isf_draft', risfdep )
               CALL iom_close( inum )
               WHERE( bathy(:,:) <= 0._wp )  risfdep(:,:) = 0._wp

               ! set grounded point to 0 
               ! (a treshold could be set here if needed, or set it offline based on the grounded fraction)
               WHERE ( bathy(:,:) <= risfdep(:,:) + rn_isfhmin )
                  misfdep(:,:) = 0 ; risfdep(:,:) = 0._wp
                  mbathy (:,:) = 0 ; bathy  (:,:) = 0._wp
               END WHERE
            END IF
            !       
            IF( cp_cfg == "orca" .AND. jp_cfg == 2 ) THEN    ! ORCA R2 configuration
            !
              ii0 = 140   ;   ii1 = 140                   ! Gibraltar Strait open 
              ij0 = 102   ;   ij1 = 102                   ! (Thomson, Ocean Modelling, 1995)
              DO ji = mi0(ii0), mi1(ii1)
                 DO jj = mj0(ij0), mj1(ij1)
                    bathy(ji,jj) = 284._wp
                 END DO
               END DO
              IF(lwp) WRITE(numout,*)     
              IF(lwp) WRITE(numout,*) '      orca_r2: Gibraltar strait open at i=',ii0,' j=',ij0
              !
              ii0 = 160   ;   ii1 = 160                   ! Bab el mandeb Strait open
              ij0 = 88    ;   ij1 = 88                    ! (Thomson, Ocean Modelling, 1995)
               DO ji = mi0(ii0), mi1(ii1)
                 DO jj = mj0(ij0), mj1(ij1)
                    bathy(ji,jj) = 137._wp
                 END DO
              END DO
              IF(lwp) WRITE(numout,*)
               IF(lwp) WRITE(numout,*) '             orca_r2: Bab el Mandeb strait open at i=',ii0,' j=',ij0
              !
           ENDIF
            !
        ENDIF
         !                                            ! =============== !
      ELSE                                            !      error      !
         !                                            ! =============== !
         WRITE(ctmp1,*) 'parameter , ntopo = ', ntopo
         CALL ctl_stop( '    zgr_bat : '//trim(ctmp1) )
      ENDIF
      !
      IF( nn_closea == 0 )   CALL clo_bat( bathy, mbathy )    !==  NO closed seas or lakes  ==!
      !                       
      IF ( (.not. ln_sco) .AND. (.not. ln_mes) ) THEN          !==  set a minimum depth  ==!
         IF( rn_hmin < 0._wp ) THEN    ;   ik = - INT( rn_hmin )                                      ! from a nb of level
         ELSE                          ;   ik = MINLOC( gdepw_1d, mask = gdepw_1d > rn_hmin, dim = 1 )  ! from a depth
         ENDIF
         zhmin = gdepw_1d(ik+1)                                                         ! minimum depth = ik+1 w-levels 
         WHERE( bathy(:,:) <= 0._wp )   ;   bathy(:,:) = 0._wp                         ! min=0     over the lands
         ELSE WHERE                     ;   bathy(:,:) = MAX(  zhmin , bathy(:,:)  )   ! min=zhmin over the oceans
         END WHERE
         IF(lwp) write(numout,*) 'Minimum ocean depth: ', zhmin, ' minimum number of ocean levels : ', ik
      ENDIF
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_bat')
      !
   END SUBROUTINE zgr_bat


   SUBROUTINE zgr_bat_zoom
      !!----------------------------------------------------------------------
      !!                    ***  ROUTINE zgr_bat_zoom  ***
      !!
      !! ** Purpose : - Close zoom domain boundary if necessary
      !!              - Suppress Med Sea from ORCA R2 and R05 arctic zoom
      !!
      !! ** Method  : 
      !!
      !! ** Action  : - update mbathy: level bathymetry (in level index)
      !!----------------------------------------------------------------------
      INTEGER ::   ii0, ii1, ij0, ij1   ! temporary integers
      !!----------------------------------------------------------------------
      !
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*) '    zgr_bat_zoom : modify the level bathymetry for zoom domain'
      IF(lwp) WRITE(numout,*) '    ~~~~~~~~~~~~'
      !
      ! Zoom domain
      ! ===========
      !
      ! Forced closed boundary if required
      IF( lzoom_s )   mbathy(  : , mj0(jpjzoom):mj1(jpjzoom) )      = 0
      IF( lzoom_w )   mbathy(      mi0(jpizoom):mi1(jpizoom) , :  ) = 0
      IF( lzoom_e )   mbathy(      mi0(jpiglo+jpizoom-1):mi1(jpiglo+jpizoom-1) , :  ) = 0
      IF( lzoom_n )   mbathy(  : , mj0(jpjglo+jpjzoom-1):mj1(jpjglo+jpjzoom-1) )      = 0
      !
      ! Configuration specific domain modifications
      ! (here, ORCA arctic configuration: suppress Med Sea)
      IF( cp_cfg == "orca" .AND. cp_cfz == "arctic" ) THEN
         SELECT CASE ( jp_cfg )
         !                                        ! =======================
         CASE ( 2 )                               !  ORCA_R2 configuration
            !                                     ! =======================
            IF(lwp) WRITE(numout,*) '                   ORCA R2 arctic zoom: suppress the Med Sea'
            ii0 = 141   ;   ii1 = 162      ! Sea box i,j indices
            ij0 =  98   ;   ij1 = 110
            !                                     ! =======================
         CASE ( 05 )                              !  ORCA_R05 configuration
            !                                     ! =======================
            IF(lwp) WRITE(numout,*) '                   ORCA R05 arctic zoom: suppress the Med Sea'
            ii0 = 563   ;   ii1 = 642      ! zero over the Med Sea boxe
            ij0 = 314   ;   ij1 = 370 
         END SELECT
         !
         mbathy( mi0(ii0):mi1(ii1) , mj0(ij0):mj1(ij1) ) = 0   ! zero over the Med Sea boxe
         !
      ENDIF
      !
   END SUBROUTINE zgr_bat_zoom


   SUBROUTINE zgr_bat_ctl
      !!----------------------------------------------------------------------
      !!                    ***  ROUTINE zgr_bat_ctl  ***
      !!
      !! ** Purpose :   check the bathymetry in levels
      !!
      !! ** Method  :   The array mbathy is checked to verified its consistency
      !!      with the model options. in particular:
      !!            mbathy must have at least 1 land grid-points (mbathy<=0)
      !!                  along closed boundary.
      !!            mbathy must be cyclic IF jperio=1.
      !!            mbathy must be lower or equal to jpk-1.
      !!            isolated ocean grid points are suppressed from mbathy
      !!                  since they are only connected to remaining
      !!                  ocean through vertical diffusion.
      !!      C A U T I O N : mbathy will be modified during the initializa-
      !!      tion phase to become the number of non-zero w-levels of a water
      !!      column, with a minimum value of 1.
      !!
      !! ** Action  : - update mbathy: level bathymetry (in level index)
      !!              - update bathy : meter bathymetry (in meters)
      !!----------------------------------------------------------------------
      INTEGER ::   ji, jj, jl                    ! dummy loop indices
      INTEGER ::   icompt, ibtest, ikmax         ! temporary integers
      REAL(wp), POINTER, DIMENSION(:,:) ::  zbathy
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_bat_ctl')
      !
      CALL wrk_alloc( jpi, jpj, zbathy )
      !
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*) '    zgr_bat_ctl : check the bathymetry'
      IF(lwp) WRITE(numout,*) '    ~~~~~~~~~~~'
      !                                          ! Suppress isolated ocean grid points
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*)'                   suppress isolated ocean grid points'
      IF(lwp) WRITE(numout,*)'                   -----------------------------------'
      icompt = 0
      DO jl = 1, 2
         IF( nperio == 1 .OR. nperio  ==  4 .OR. nperio  ==  6 ) THEN
            mbathy( 1 ,:) = mbathy(jpim1,:)           ! local domain is cyclic east-west
            mbathy(jpi,:) = mbathy(  2  ,:)
         ENDIF
         DO jj = 2, jpjm1
            DO ji = 2, jpim1
               ibtest = MAX(  mbathy(ji-1,jj), mbathy(ji+1,jj),   &
                  &           mbathy(ji,jj-1), mbathy(ji,jj+1)  )
               IF( ibtest < mbathy(ji,jj) ) THEN
                  IF(lwp) WRITE(numout,*) ' the number of ocean level at ',   &
                     &   'grid-point (i,j) =  ',ji,jj,' is changed from ', mbathy(ji,jj),' to ', ibtest
                  mbathy(ji,jj) = ibtest
                  icompt = icompt + 1
               ENDIF
            END DO
         END DO
      END DO
      IF( lk_mpp )   CALL mpp_sum( icompt )
      IF( icompt == 0 ) THEN
         IF(lwp) WRITE(numout,*)'     no isolated ocean grid points'
      ELSE
         IF(lwp) WRITE(numout,*)'    ',icompt,' ocean grid points suppressed'
      ENDIF
      IF( lk_mpp ) THEN
         zbathy(:,:) = FLOAT( mbathy(:,:) )
         CALL lbc_lnk( zbathy, 'T', 1._wp )
         mbathy(:,:) = INT( zbathy(:,:) )
      ENDIF
      !                                          ! East-west cyclic boundary conditions
      IF( nperio == 0 ) THEN
         IF(lwp) WRITE(numout,*) ' mbathy set to 0 along east and west boundary: nperio = ', nperio
         IF( lk_mpp ) THEN
            IF( nbondi == -1 .OR. nbondi == 2 ) THEN
               IF( jperio /= 1 )   mbathy(1,:) = 0
            ENDIF
            IF( nbondi == 1 .OR. nbondi == 2 ) THEN
               IF( jperio /= 1 )   mbathy(nlci,:) = 0
            ENDIF
         ELSE
            IF( ln_zco .OR. ln_zps ) THEN
               mbathy( 1 ,:) = 0
               mbathy(jpi,:) = 0
            ELSE
               mbathy( 1 ,:) = jpkm1
               mbathy(jpi,:) = jpkm1
            ENDIF
         ENDIF
      ELSEIF( nperio == 1 .OR. nperio == 4 .OR. nperio ==  6 ) THEN
         IF(lwp) WRITE(numout,*)' east-west cyclic boundary conditions on mbathy: nperio = ', nperio
         mbathy( 1 ,:) = mbathy(jpim1,:)
         mbathy(jpi,:) = mbathy(  2  ,:)
      ELSEIF( nperio == 2 ) THEN
         IF(lwp) WRITE(numout,*) '   equatorial boundary conditions on mbathy: nperio = ', nperio
      ELSE
         IF(lwp) WRITE(numout,*) '    e r r o r'
         IF(lwp) WRITE(numout,*) '    parameter , nperio = ', nperio
         !         STOP 'dom_mba'
      ENDIF
      !  Boundary condition on mbathy
      IF( .NOT.lk_mpp ) THEN 
!!gm     !!bug ???  think about it !
         !   ... mono- or macro-tasking: T-point, >0, 2D array, no slab
         zbathy(:,:) = FLOAT( mbathy(:,:) )
         CALL lbc_lnk( zbathy, 'T', 1._wp )
         mbathy(:,:) = INT( zbathy(:,:) )
      ENDIF
      ! Number of ocean level inferior or equal to jpkm1
      ikmax = 0
      DO jj = 1, jpj
         DO ji = 1, jpi
            ikmax = MAX( ikmax, mbathy(ji,jj) )
         END DO
      END DO
!!gm  !!! test to do:   ikmax = MAX( mbathy(:,:) )   ???
      IF( ikmax > jpkm1 ) THEN
         IF(lwp) WRITE(numout,*) ' maximum number of ocean level = ', ikmax,' >  jpk-1'
         IF(lwp) WRITE(numout,*) ' change jpk to ',ikmax+1,' to use the exact ead bathymetry'
      ELSE IF( ikmax < jpkm1 ) THEN
         IF(lwp) WRITE(numout,*) ' maximum number of ocean level = ', ikmax,' < jpk-1' 
         IF(lwp) WRITE(numout,*) ' you can decrease jpk to ', ikmax+1
      ENDIF
      !
      CALL wrk_dealloc( jpi, jpj, zbathy )
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_bat_ctl')
      !
   END SUBROUTINE zgr_bat_ctl


   SUBROUTINE zgr_bot_level
      !!----------------------------------------------------------------------
      !!                    ***  ROUTINE zgr_bot_level  ***
      !!
      !! ** Purpose :   defines the vertical index of ocean bottom (mbk. arrays)
      !!
      !! ** Method  :   computes from mbathy with a minimum value of 1 over land
      !!
      !! ** Action  :   mbkt, mbku, mbkv :   vertical indices of the deeptest 
      !!                                     ocean level at t-, u- & v-points
      !!                                     (min value = 1 over land)
      !!----------------------------------------------------------------------
      INTEGER ::   ji, jj   ! dummy loop indices
      REAL(wp), POINTER, DIMENSION(:,:) ::  zmbk
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_bot_level')
      !
      CALL wrk_alloc( jpi, jpj, zmbk )
      !
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*) '    zgr_bot_level : ocean bottom k-index of T-, U-, V- and W-levels '
      IF(lwp) WRITE(numout,*) '    ~~~~~~~~~~~~~'
      !
      mbkt(:,:) = MAX( mbathy(:,:) , 1 )    ! bottom k-index of T-level (=1 over land)
 
      !                                     ! bottom k-index of W-level = mbkt+1
      DO jj = 1, jpjm1                      ! bottom k-index of u- (v-) level
         DO ji = 1, jpim1
            mbku(ji,jj) = MIN(  mbkt(ji+1,jj  ) , mbkt(ji,jj)  )
            mbkv(ji,jj) = MIN(  mbkt(ji  ,jj+1) , mbkt(ji,jj)  )
         END DO
      END DO
      ! converte into REAL to use lbc_lnk ; impose a min value of 1 as a zero can be set in lbclnk 
      zmbk(:,:) = REAL( mbku(:,:), wp )   ;   CALL lbc_lnk(zmbk,'U',1.)   ;   mbku  (:,:) = MAX( INT( zmbk(:,:) ), 1 )
      zmbk(:,:) = REAL( mbkv(:,:), wp )   ;   CALL lbc_lnk(zmbk,'V',1.)   ;   mbkv  (:,:) = MAX( INT( zmbk(:,:) ), 1 )
      !
      CALL wrk_dealloc( jpi, jpj, zmbk )
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_bot_level')
      !
   END SUBROUTINE zgr_bot_level


   SUBROUTINE zgr_top_level
      !!----------------------------------------------------------------------
      !!                    ***  ROUTINE zgr_top_level  ***
      !!
      !! ** Purpose :   defines the vertical index of ocean top (mik. arrays)
      !!
      !! ** Method  :   computes from misfdep with a minimum value of 1
      !!
      !! ** Action  :   mikt, miku, mikv :   vertical indices of the shallowest 
      !!                                     ocean level at t-, u- & v-points
      !!                                     (min value = 1)
      !!----------------------------------------------------------------------
      INTEGER ::   ji, jj   ! dummy loop indices
      REAL(wp), POINTER, DIMENSION(:,:) ::  zmik
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_top_level')
      !
      CALL wrk_alloc( jpi, jpj, zmik )
      !
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*) '    zgr_top_level : ocean top k-index of T-, U-, V- and W-levels '
      IF(lwp) WRITE(numout,*) '    ~~~~~~~~~~~~~'
      !
      mikt(:,:) = MAX( misfdep(:,:) , 1 )    ! top k-index of T-level (=1)
      !                                      ! top k-index of W-level (=mikt)
      DO jj = 1, jpjm1                       ! top k-index of U- (U-) level
         DO ji = 1, jpim1
            miku(ji,jj) = MAX(  mikt(ji+1,jj  ) , mikt(ji,jj)  )
            mikv(ji,jj) = MAX(  mikt(ji  ,jj+1) , mikt(ji,jj)  )
            mikf(ji,jj) = MAX(  mikt(ji  ,jj+1) , mikt(ji,jj), mikt(ji+1,jj  ), mikt(ji+1,jj+1)  )
         END DO
      END DO

      ! converte into REAL to use lbc_lnk ; impose a min value of 1 as a zero can be set in lbclnk 
      zmik(:,:) = REAL( miku(:,:), wp )   ;   CALL lbc_lnk(zmik,'U',1.)   ;   miku  (:,:) = MAX( INT( zmik(:,:) ), 1 )
      zmik(:,:) = REAL( mikv(:,:), wp )   ;   CALL lbc_lnk(zmik,'V',1.)   ;   mikv  (:,:) = MAX( INT( zmik(:,:) ), 1 )
      zmik(:,:) = REAL( mikf(:,:), wp )   ;   CALL lbc_lnk(zmik,'F',1.)   ;   mikf  (:,:) = MAX( INT( zmik(:,:) ), 1 )
      !
      CALL wrk_dealloc( jpi, jpj, zmik )
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_top_level')
      !
   END SUBROUTINE zgr_top_level


   SUBROUTINE zgr_zco
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE zgr_zco  ***
      !!
      !! ** Purpose :   define the reference z-coordinate system
      !!
      !! ** Method  :   set 3D coord. arrays to reference 1D array 
      !!----------------------------------------------------------------------
      INTEGER  ::   jk
      !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_zco')
      !
      DO jk = 1, jpk
         gdept_0(:,:,jk) = gdept_1d(jk)
         gdepw_0(:,:,jk) = gdepw_1d(jk)
         gde3w_0(:,:,jk) = gdepw_1d(jk)
         e3t_0  (:,:,jk) = e3t_1d  (jk)
         e3u_0  (:,:,jk) = e3t_1d  (jk)
         e3v_0  (:,:,jk) = e3t_1d  (jk)
         e3f_0  (:,:,jk) = e3t_1d  (jk)
         e3w_0  (:,:,jk) = e3w_1d  (jk)
         e3uw_0 (:,:,jk) = e3w_1d  (jk)
         e3vw_0 (:,:,jk) = e3w_1d  (jk)
      END DO
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_zco')
      !
   END SUBROUTINE zgr_zco


   SUBROUTINE zgr_zps
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE zgr_zps  ***
      !!                     
      !! ** Purpose :   the depth and vertical scale factor in partial step
      !!              reference z-coordinate case
      !!
      !! ** Method  :   Partial steps : computes the 3D vertical scale factors
      !!      of T-, U-, V-, W-, UW-, VW and F-points that are associated with
      !!      a partial step representation of bottom topography.
      !!
      !!        The reference depth of model levels is defined from an analytical
      !!      function the derivative of which gives the reference vertical
      !!      scale factors.
      !!        From  depth and scale factors reference, we compute there new value
      !!      with partial steps  on 3d arrays ( i, j, k ).
      !!
      !!              w-level: gdepw_0(i,j,k)  = gdep(k)
      !!                       e3w_0(i,j,k) = dk(gdep)(k)     = e3(i,j,k)
      !!              t-level: gdept_0(i,j,k)  = gdep(k+0.5)
      !!                       e3t_0(i,j,k) = dk(gdep)(k+0.5) = e3(i,j,k+0.5)
      !!
      !!        With the help of the bathymetric file ( bathymetry_depth_ORCA_R2.nc),
      !!      we find the mbathy index of the depth at each grid point.
      !!      This leads us to three cases:
      !!
      !!              - bathy = 0 => mbathy = 0
      !!              - 1 < mbathy < jpkm1    
      !!              - bathy > gdepw_0(jpk) => mbathy = jpkm1  
      !!
      !!        Then, for each case, we find the new depth at t- and w- levels
      !!      and the new vertical scale factors at t-, u-, v-, w-, uw-, vw- 
      !!      and f-points.
      !! 
      !!        This routine is given as an example, it must be modified
      !!      following the user s desiderata. nevertheless, the output as
      !!      well as the way to compute the model levels and scale factors
      !!      must be respected in order to insure second order accuracy
      !!      schemes.
      !!
      !!         c a u t i o n : gdept_1d, gdepw_1d and e3._1d are positives
      !!         - - - - - - -   gdept_0, gdepw_0 and e3. are positives
      !!      
      !!  Reference :   Pacanowsky & Gnanadesikan 1997, Mon. Wea. Rev., 126, 3248-3270.
      !!----------------------------------------------------------------------
      INTEGER  ::   ji, jj, jk       ! dummy loop indices
      INTEGER  ::   ik, it, ikb, ikt ! temporary integers
      REAL(wp) ::   ze3tp , ze3wp    ! Last ocean level thickness at T- and W-points
      REAL(wp) ::   zdepwp, zdepth   ! Ajusted ocean depth to avoid too small e3t
      REAL(wp) ::   zdiff            ! temporary scalar
      REAL(wp) ::   zmax             ! temporary scalar
      REAL(wp), POINTER, DIMENSION(:,:,:) ::  zprt
      !!---------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_zps')
      !
      CALL wrk_alloc( jpi,jpj,jpk,   zprt )
      !
      IF(lwp) WRITE(numout,*)
      IF(lwp) WRITE(numout,*) '    zgr_zps : z-coordinate with partial steps'
      IF(lwp) WRITE(numout,*) '    ~~~~~~~ '
      IF(lwp) WRITE(numout,*) '              mbathy is recomputed : bathy_level file is NOT used'

      ! bathymetry in level (from bathy_meter)
      ! ===================
      zmax = gdepw_1d(jpk) + e3t_1d(jpk)        ! maximum depth (i.e. the last ocean level thickness <= 2*e3t_1d(jpkm1) )
      bathy(:,:) = MIN( zmax ,  bathy(:,:) )    ! bounded value of bathy (min already set at the end of zgr_bat)
      WHERE( bathy(:,:) == 0._wp )   ;   mbathy(:,:) = 0       ! land  : set mbathy to 0
      ELSE WHERE                     ;   mbathy(:,:) = jpkm1   ! ocean : initialize mbathy to the max ocean level
      END WHERE

      ! Compute mbathy for ocean points (i.e. the number of ocean levels)
      ! find the number of ocean levels such that the last level thickness
      ! is larger than the minimum of e3zps_min and e3zps_rat * e3t_1d (where
      ! e3t_1d is the reference level thickness
      DO jk = jpkm1, 1, -1
         zdepth = gdepw_1d(jk) + MIN( e3zps_min, e3t_1d(jk)*e3zps_rat )
         WHERE( 0._wp < bathy(:,:) .AND. bathy(:,:) <= zdepth )   mbathy(:,:) = jk-1
      END DO

      ! Scale factors and depth at T- and W-points
      DO jk = 1, jpk                        ! intitialization to the reference z-coordinate
         gdept_0(:,:,jk) = gdept_1d(jk)
         gdepw_0(:,:,jk) = gdepw_1d(jk)
         e3t_0  (:,:,jk) = e3t_1d  (jk)
         e3w_0  (:,:,jk) = e3w_1d  (jk)
      END DO
      
      ! Bathy, iceshelf draft, scale factor and depth at T- and W- points in case of isf
      IF ( ln_isfcav ) CALL zgr_isf

      ! Scale factors and depth at T- and W-points
      IF ( .NOT. ln_isfcav ) THEN
         DO jj = 1, jpj
            DO ji = 1, jpi
               ik = mbathy(ji,jj)
               IF( ik > 0 ) THEN               ! ocean point only
                  ! max ocean level case
                  IF( ik == jpkm1 ) THEN
                     zdepwp = bathy(ji,jj)
                     ze3tp  = bathy(ji,jj) - gdepw_1d(ik)
                     ze3wp = 0.5_wp * e3w_1d(ik) * ( 1._wp + ( ze3tp/e3t_1d(ik) ) )
                     e3t_0(ji,jj,ik  ) = ze3tp
                     e3t_0(ji,jj,ik+1) = ze3tp
                     e3w_0(ji,jj,ik  ) = ze3wp
                     e3w_0(ji,jj,ik+1) = ze3tp
                     gdepw_0(ji,jj,ik+1) = zdepwp
                     gdept_0(ji,jj,ik  ) = gdept_1d(ik-1) + ze3wp
                     gdept_0(ji,jj,ik+1) = gdept_0(ji,jj,ik) + ze3tp
                     !
                  ELSE                         ! standard case
                     IF( bathy(ji,jj) <= gdepw_1d(ik+1) ) THEN  ;   gdepw_0(ji,jj,ik+1) = bathy(ji,jj)
                     ELSE                                       ;   gdepw_0(ji,jj,ik+1) = gdepw_1d(ik+1)
                     ENDIF
   !gm Bug?  check the gdepw_1d
                     !       ... on ik
                     gdept_0(ji,jj,ik) = gdepw_1d(ik) + ( gdepw_0(ji,jj,ik+1) - gdepw_1d(ik) )   &
                        &                             * ((gdept_1d(     ik  ) - gdepw_1d(ik) )   &
                        &                             / ( gdepw_1d(     ik+1) - gdepw_1d(ik) ))
                     e3t_0  (ji,jj,ik) = e3t_1d  (ik) * ( gdepw_0 (ji,jj,ik+1) - gdepw_1d(ik) )   & 
                        &                             / ( gdepw_1d(      ik+1) - gdepw_1d(ik) ) 
                     e3w_0(ji,jj,ik) = 0.5_wp * ( gdepw_0(ji,jj,ik+1) + gdepw_1d(ik+1) - 2._wp * gdepw_1d(ik) )   &
                        &                     * ( e3w_1d(ik) / ( gdepw_1d(ik+1) - gdepw_1d(ik) ) )
                     !       ... on ik+1
                     e3w_0  (ji,jj,ik+1) = e3t_0  (ji,jj,ik)
                     e3t_0  (ji,jj,ik+1) = e3t_0  (ji,jj,ik)
                     gdept_0(ji,jj,ik+1) = gdept_0(ji,jj,ik) + e3t_0(ji,jj,ik)
                  ENDIF
               ENDIF
            END DO
         END DO
         !
         it = 0
         DO jj = 1, jpj
            DO ji = 1, jpi
               ik = mbathy(ji,jj)
               IF( ik > 0 ) THEN               ! ocean point only
                  e3tp (ji,jj) = e3t_0(ji,jj,ik)
                  e3wp (ji,jj) = e3w_0(ji,jj,ik)
                  ! test
                  zdiff= gdepw_0(ji,jj,ik+1) - gdept_0(ji,jj,ik  )
                  IF( zdiff <= 0._wp .AND. lwp ) THEN 
                     it = it + 1
                     WRITE(numout,*) ' it      = ', it, ' ik      = ', ik, ' (i,j) = ', ji, jj
                     WRITE(numout,*) ' bathy = ', bathy(ji,jj)
                     WRITE(numout,*) ' gdept_0 = ', gdept_0(ji,jj,ik), ' gdepw_0 = ', gdepw_0(ji,jj,ik+1), ' zdiff = ', zdiff
                     WRITE(numout,*) ' e3tp    = ', e3t_0  (ji,jj,ik), ' e3wp    = ', e3w_0  (ji,jj,ik  )
                  ENDIF
               ENDIF
            END DO
         END DO
      END IF
      !
      ! Scale factors and depth at U-, V-, UW and VW-points
      DO jk = 1, jpk                        ! initialisation to z-scale factors
         e3u_0 (:,:,jk) = e3t_1d(jk)
         e3v_0 (:,:,jk) = e3t_1d(jk)
         e3uw_0(:,:,jk) = e3w_1d(jk)
         e3vw_0(:,:,jk) = e3w_1d(jk)
      END DO

      DO jk = 1,jpk                         ! Computed as the minimum of neighbooring scale factors
         DO jj = 1, jpjm1
            DO ji = 1, jpim1   ! vector opt.
               e3u_0 (ji,jj,jk) = MIN( e3t_0(ji,jj,jk), e3t_0(ji+1,jj,jk) )
               e3v_0 (ji,jj,jk) = MIN( e3t_0(ji,jj,jk), e3t_0(ji,jj+1,jk) )
               e3uw_0(ji,jj,jk) = MIN( e3w_0(ji,jj,jk), e3w_0(ji+1,jj,jk) )
               e3vw_0(ji,jj,jk) = MIN( e3w_0(ji,jj,jk), e3w_0(ji,jj+1,jk) )
            END DO
         END DO
      END DO
      IF ( ln_isfcav ) THEN
      ! (ISF) define e3uw (adapted for 2 cells in the water column)
         DO jj = 2, jpjm1 
            DO ji = 2, jpim1   ! vector opt. 
               ikb = MAX(mbathy (ji,jj),mbathy (ji+1,jj))
               ikt = MAX(misfdep(ji,jj),misfdep(ji+1,jj))
               IF (ikb == ikt+1) e3uw_0(ji,jj,ikb) =  MIN( gdept_0(ji,jj,ikb  ), gdept_0(ji+1,jj  ,ikb  ) ) &
                                       &            - MAX( gdept_0(ji,jj,ikb-1), gdept_0(ji+1,jj  ,ikb-1) )
               ikb = MAX(mbathy (ji,jj),mbathy (ji,jj+1))
               ikt = MAX(misfdep(ji,jj),misfdep(ji,jj+1))
               IF (ikb == ikt+1) e3vw_0(ji,jj,ikb) =  MIN( gdept_0(ji,jj,ikb  ), gdept_0(ji  ,jj+1,ikb  ) ) &
                                       &            - MAX( gdept_0(ji,jj,ikb-1), gdept_0(ji  ,jj+1,ikb-1) )
            END DO
         END DO
      END IF

      CALL lbc_lnk( e3u_0 , 'U', 1._wp )   ;   CALL lbc_lnk( e3uw_0, 'U', 1._wp )   ! lateral boundary conditions
      CALL lbc_lnk( e3v_0 , 'V', 1._wp )   ;   CALL lbc_lnk( e3vw_0, 'V', 1._wp )
      !

      DO jk = 1, jpk                        ! set to z-scale factor if zero (i.e. along closed boundaries)
         WHERE( e3u_0 (:,:,jk) == 0._wp )   e3u_0 (:,:,jk) = e3t_1d(jk)
         WHERE( e3v_0 (:,:,jk) == 0._wp )   e3v_0 (:,:,jk) = e3t_1d(jk)
         WHERE( e3uw_0(:,:,jk) == 0._wp )   e3uw_0(:,:,jk) = e3w_1d(jk)
         WHERE( e3vw_0(:,:,jk) == 0._wp )   e3vw_0(:,:,jk) = e3w_1d(jk)
      END DO
      
      ! Scale factor at F-point
      DO jk = 1, jpk                        ! initialisation to z-scale factors
         e3f_0(:,:,jk) = e3t_1d(jk)
      END DO
      DO jk = 1, jpk                        ! Computed as the minimum of neighbooring V-scale factors
         DO jj = 1, jpjm1
            DO ji = 1, jpim1   ! vector opt.
               e3f_0(ji,jj,jk) = MIN( e3v_0(ji,jj,jk), e3v_0(ji+1,jj,jk) )
            END DO
         END DO
      END DO
      CALL lbc_lnk( e3f_0, 'F', 1._wp )       ! Lateral boundary conditions
      !
      DO jk = 1, jpk                        ! set to z-scale factor if zero (i.e. along closed boundaries)
         WHERE( e3f_0(:,:,jk) == 0._wp )   e3f_0(:,:,jk) = e3t_1d(jk)
      END DO
!!gm  bug ? :  must be a do loop with mj0,mj1
      ! 
      e3t_0(:,mj0(1),:) = e3t_0(:,mj0(2),:)     ! we duplicate factor scales for jj = 1 and jj = 2
      e3w_0(:,mj0(1),:) = e3w_0(:,mj0(2),:) 
      e3u_0(:,mj0(1),:) = e3u_0(:,mj0(2),:) 
      e3v_0(:,mj0(1),:) = e3v_0(:,mj0(2),:) 
      e3f_0(:,mj0(1),:) = e3f_0(:,mj0(2),:) 

      ! Control of the sign
      IF( MINVAL( e3t_0  (:,:,:) ) <= 0._wp )   CALL ctl_stop( '    zgr_zps :   e r r o r   e3t_0 <= 0' )
      IF( MINVAL( e3w_0  (:,:,:) ) <= 0._wp )   CALL ctl_stop( '    zgr_zps :   e r r o r   e3w_0 <= 0' )
      IF( MINVAL( gdept_0(:,:,:) ) <  0._wp )   CALL ctl_stop( '    zgr_zps :   e r r o r   gdept_0 <  0' )
      IF( MINVAL( gdepw_0(:,:,:) ) <  0._wp )   CALL ctl_stop( '    zgr_zps :   e r r o r   gdepw_0 <  0' )
     
      ! Compute gde3w_0 (vertical sum of e3w)
      IF ( ln_isfcav ) THEN ! if cavity
         WHERE( misfdep == 0 )   misfdep = 1
         DO jj = 1,jpj
            DO ji = 1,jpi
               gde3w_0(ji,jj,1) = 0.5_wp * e3w_0(ji,jj,1)
               DO jk = 2, misfdep(ji,jj)
                  gde3w_0(ji,jj,jk) = gde3w_0(ji,jj,jk-1) + e3w_0(ji,jj,jk) 
               END DO
               IF( misfdep(ji,jj) >= 2 )   gde3w_0(ji,jj,misfdep(ji,jj)) = risfdep(ji,jj) + 0.5_wp * e3w_0(ji,jj,misfdep(ji,jj))
               DO jk = misfdep(ji,jj) + 1, jpk
                  gde3w_0(ji,jj,jk) = gde3w_0(ji,jj,jk-1) + e3w_0(ji,jj,jk) 
               END DO
            END DO
         END DO
      ELSE ! no cavity
         gde3w_0(:,:,1) = 0.5_wp * e3w_0(:,:,1)
         DO jk = 2, jpk
            gde3w_0(:,:,jk) = gde3w_0(:,:,jk-1) + e3w_0(:,:,jk)
         END DO
      END IF
      !
      CALL wrk_dealloc( jpi,jpj,jpk,   zprt )
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_zps')
      !
   END SUBROUTINE zgr_zps


   SUBROUTINE zgr_isf
      !!----------------------------------------------------------------------
      !!                    ***  ROUTINE zgr_isf  ***
      !!   
      !! ** Purpose :   check the bathymetry in levels
      !!   
      !! ** Method  :   THe water column have to contained at least 2 cells
      !!                Bathymetry and isfdraft are modified (dig/close) to respect
      !!                this criterion.
      !!   
      !! ** Action  : - test compatibility between isfdraft and bathy 
      !!              - bathy and isfdraft are modified
      !!----------------------------------------------------------------------
      INTEGER  ::   ji, jj, jl, jk       ! dummy loop indices
      INTEGER  ::   ik, it               ! temporary integers
      INTEGER  ::   icompt, ibtest       ! (ISF)
      INTEGER  ::   ibtestim1, ibtestip1 ! (ISF)
      INTEGER  ::   ibtestjm1, ibtestjp1 ! (ISF)
      REAL(wp) ::   zdepth           ! Ajusted ocean depth to avoid too small e3t
      REAL(wp) ::   zmax             ! Maximum and minimum depth
      REAL(wp) ::   zbathydiff       ! isf temporary scalar
      REAL(wp) ::   zrisfdepdiff     ! isf temporary scalar
      REAL(wp) ::   ze3tp , ze3wp    ! Last ocean level thickness at T- and W-points
      REAL(wp) ::   zdepwp           ! Ajusted ocean depth to avoid too small e3t
      REAL(wp) ::   zdiff            ! temporary scalar
      REAL(wp), POINTER, DIMENSION(:,:)   ::   zrisfdep, zbathy, zmask   ! 2D workspace (ISH)
      INTEGER , POINTER, DIMENSION(:,:)   ::   zmbathy, zmisfdep         ! 2D workspace (ISH)
      !!---------------------------------------------------------------------
      !
      IF( nn_timing == 1 )   CALL timing_start('zgr_isf')
      !
      CALL wrk_alloc( jpi,jpj,   zbathy, zmask, zrisfdep)
      CALL wrk_alloc( jpi,jpj,   zmisfdep, zmbathy )

      ! (ISF) compute misfdep
      WHERE( risfdep(:,:) == 0._wp .AND. bathy(:,:) /= 0 ) ;   misfdep(:,:) = 1   ! open water : set misfdep to 1  
      ELSEWHERE                      ;                         misfdep(:,:) = 2   ! iceshelf : initialize misfdep to second level 
      END WHERE  

      ! Compute misfdep for ocean points (i.e. first wet level) 
      ! find the first ocean level such that the first level thickness 
      ! is larger than the bot_level of e3zps_min and e3zps_rat * e3t_0 (where 
      ! e3t_0 is the reference level thickness 
      DO jk = 2, jpkm1 
         zdepth = gdepw_1d(jk+1) - MIN( e3zps_min, e3t_1d(jk)*e3zps_rat ) 
         WHERE( 0._wp < risfdep(:,:) .AND. risfdep(:,:) >= zdepth )   misfdep(:,:) = jk+1 
      END DO 
      WHERE ( 0._wp < risfdep(:,:) .AND. risfdep(:,:) <= e3t_1d(1) )
         risfdep(:,:) = 0. ; misfdep(:,:) = 1
      END WHERE

      ! remove very shallow ice shelf (less than ~ 10m if 75L)
      WHERE (risfdep(:,:) <= 10._wp .AND. misfdep(:,:) > 1)
         misfdep = 0; risfdep = 0.0_wp;
         mbathy  = 0; bathy   = 0.0_wp;
      END WHERE
      WHERE (bathy(:,:) <= 30.0_wp .AND. gphit < -60._wp)
         misfdep = 0; risfdep = 0.0_wp;
         mbathy  = 0; bathy   = 0.0_wp;
      END WHERE
 
! basic check for the compatibility of bathy and risfdep. I think it should be offline because it is not perfect and cannot solved all the situation
      icompt = 0 
! run the bathy check 10 times to be sure all the modif in the bathy or iceshelf draft are compatible together
      DO jl = 1, 10     
         ! check at each iteration if isf is grounded or not (1cm treshold have to be update after first coupling experiments)
         WHERE (bathy(:,:) <= risfdep(:,:) + rn_isfhmin)
            misfdep(:,:) = 0 ; risfdep(:,:) = 0._wp
            mbathy (:,:) = 0 ; bathy  (:,:) = 0._wp
         END WHERE
         WHERE (mbathy(:,:) <= 0) 
            misfdep(:,:) = 0; risfdep(:,:) = 0._wp 
            mbathy (:,:) = 0; bathy  (:,:) = 0._wp
         END WHERE
         IF( lk_mpp ) THEN
            zbathy(:,:)  = FLOAT( misfdep(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            misfdep(:,:) = INT( zbathy(:,:) )

            CALL lbc_lnk( risfdep,'T', 1. )
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:)  = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:)  = INT( zbathy(:,:) )
         ENDIF
         IF( nperio == 1 .OR. nperio  ==  4 .OR. nperio  ==  6 ) THEN 
            misfdep( 1 ,:) = misfdep(jpim1,:)            ! local domain is cyclic east-west 
            misfdep(jpi,:) = misfdep(  2  ,:) 
            mbathy( 1 ,:)  = mbathy(jpim1,:)             ! local domain is cyclic east-west
            mbathy(jpi,:)  = mbathy(  2  ,:)
         ENDIF

         ! split last cell if possible (only where water column is 2 cell or less)
         ! if coupled to ice sheet, we do not modify the bathymetry (can be discuss).
         IF ( .NOT. ln_iscpl) THEN
            DO jk = jpkm1, 1, -1
               zmax = gdepw_1d(jk) + MIN( e3zps_min, e3t_1d(jk)*e3zps_rat )
               WHERE( gdepw_1d(jk) < bathy(:,:) .AND. bathy(:,:) <= zmax .AND. misfdep + 1 >= mbathy)
                  mbathy(:,:) = jk
                  bathy(:,:)  = zmax
               END WHERE
            END DO
         END IF
 
         ! split top cell if possible (only where water column is 2 cell or less)
         DO jk = 2, jpkm1
            zmax = gdepw_1d(jk+1) - MIN( e3zps_min, e3t_1d(jk)*e3zps_rat )
            WHERE( gdepw_1d(jk+1) > risfdep(:,:) .AND. risfdep(:,:) >= zmax .AND. misfdep + 1 >= mbathy)
               misfdep(:,:) = jk
               risfdep(:,:) = zmax
            END WHERE
         END DO

 
 ! Case where bathy and risfdep compatible but not the level variable mbathy/misfdep because of partial cell condition
         DO jj = 1, jpj
            DO ji = 1, jpi
               ! find the minimum change option:
               ! test bathy
               IF (risfdep(ji,jj) > 1) THEN
                  IF ( .NOT. ln_iscpl ) THEN
                     zbathydiff  =ABS(bathy(ji,jj)   - (gdepw_1d(mbathy (ji,jj)+1) &
                         &            + MIN( e3zps_min, e3t_1d(mbathy (ji,jj)+1)*e3zps_rat )))
                     zrisfdepdiff=ABS(risfdep(ji,jj) - (gdepw_1d(misfdep(ji,jj)  ) &
                         &            - MIN( e3zps_min, e3t_1d(misfdep(ji,jj)-1)*e3zps_rat )))
                     IF (bathy(ji,jj) > risfdep(ji,jj) .AND. mbathy(ji,jj) <  misfdep(ji,jj)) THEN
                        IF (zbathydiff <= zrisfdepdiff) THEN
                           bathy(ji,jj) = gdepw_1d(mbathy(ji,jj)) + MIN( e3zps_min, e3t_1d(mbathy(ji,jj)+1)*e3zps_rat )
                           mbathy(ji,jj)= mbathy(ji,jj) + 1
                        ELSE
                           risfdep(ji,jj) = gdepw_1d(misfdep(ji,jj)) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj)-1)*e3zps_rat )
                           misfdep(ji,jj) = misfdep(ji,jj) - 1
                        END IF
                     ENDIF
                  ELSE
                     IF (bathy(ji,jj) > risfdep(ji,jj) .AND. mbathy(ji,jj) <  misfdep(ji,jj)) THEN
                        risfdep(ji,jj) = gdepw_1d(misfdep(ji,jj)) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj)-1)*e3zps_rat )
                        misfdep(ji,jj) = misfdep(ji,jj) - 1
                     END IF
                  END IF
               END IF
            END DO
         END DO
 
         ! At least 2 levels for water thickness at T, U, and V point.
         DO jj = 1, jpj
            DO ji = 1, jpi
               ! find the minimum change option:
               ! test bathy
               IF( misfdep(ji,jj) == mbathy(ji,jj) .AND. mbathy(ji,jj) > 1) THEN
                  IF ( .NOT. ln_iscpl ) THEN 
                     zbathydiff  =ABS(bathy(ji,jj)   - ( gdepw_1d(mbathy (ji,jj)+1) &
                         &                             + MIN( e3zps_min,e3t_1d(mbathy (ji,jj)+1)*e3zps_rat )))
                     zrisfdepdiff=ABS(risfdep(ji,jj) - ( gdepw_1d(misfdep(ji,jj)  ) & 
                         &                             - MIN( e3zps_min,e3t_1d(misfdep(ji,jj)-1)*e3zps_rat )))
                     IF (zbathydiff <= zrisfdepdiff) THEN
                        mbathy(ji,jj) = mbathy(ji,jj) + 1
                        bathy(ji,jj)  = gdepw_1d(mbathy (ji,jj)) + MIN( e3zps_min, e3t_1d(mbathy(ji,jj) +1)*e3zps_rat )
                     ELSE
                        misfdep(ji,jj)= misfdep(ji,jj) - 1
                        risfdep(ji,jj) = gdepw_1d(misfdep(ji,jj)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj))*e3zps_rat )
                     END IF
                  ELSE
                     misfdep(ji,jj)= misfdep(ji,jj) - 1
                     risfdep(ji,jj)= gdepw_1d(misfdep(ji,jj)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj))*e3zps_rat )
                  END IF
               ENDIF
            END DO
         END DO
 
 ! point V mbathy(ji,jj) == misfdep(ji,jj+1) 
         DO jj = 1, jpjm1
            DO ji = 1, jpim1
               IF( misfdep(ji,jj+1) == mbathy(ji,jj) .AND. mbathy(ji,jj) > 1) THEN
                  IF ( .NOT. ln_iscpl ) THEN 
                     zbathydiff  =ABS(bathy(ji,jj    ) - ( gdepw_1d(mbathy (ji,jj)+1) &
                          &                              + MIN( e3zps_min, e3t_1d(mbathy (ji,jj  )+1)*e3zps_rat )))
                     zrisfdepdiff=ABS(risfdep(ji,jj+1) - ( gdepw_1d(misfdep(ji,jj+1)) &
                          &                              - MIN( e3zps_min, e3t_1d(misfdep(ji,jj+1)-1)*e3zps_rat )))
                     IF (zbathydiff <= zrisfdepdiff) THEN
                        mbathy(ji,jj) = mbathy(ji,jj) + 1
                        bathy(ji,jj)  = gdepw_1d(mbathy (ji,jj  )) + MIN( e3zps_min, e3t_1d(mbathy(ji,jj   )+1)*e3zps_rat )
                     ELSE
                        misfdep(ji,jj+1)  = misfdep(ji,jj+1) - 1
                        risfdep (ji,jj+1) = gdepw_1d(misfdep(ji,jj+1)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj+1))*e3zps_rat )
                     END IF
                  ELSE
                     misfdep(ji,jj+1)  = misfdep(ji,jj+1) - 1
                     risfdep (ji,jj+1) = gdepw_1d(misfdep(ji,jj+1)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj+1))*e3zps_rat )
                  END IF
               ENDIF
            END DO
         END DO
 
         IF( lk_mpp ) THEN
            zbathy(:,:)  = FLOAT( misfdep(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            misfdep(:,:) = INT( zbathy(:,:) )

            CALL lbc_lnk( risfdep,'T', 1. )
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:)  = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:)  = INT( zbathy(:,:) )
         ENDIF
 ! point V misdep(ji,jj) == mbathy(ji,jj+1) 
         DO jj = 1, jpjm1
            DO ji = 1, jpim1
               IF( misfdep(ji,jj) == mbathy(ji,jj+1) .AND. mbathy(ji,jj) > 1) THEN
                  IF ( .NOT. ln_iscpl ) THEN 
                     zbathydiff  =ABS(  bathy(ji,jj+1) - ( gdepw_1d(mbathy (ji,jj+1)+1) &
                           &                             + MIN( e3zps_min, e3t_1d(mbathy (ji,jj+1)+1)*e3zps_rat )))
                     zrisfdepdiff=ABS(risfdep(ji,jj  ) - ( gdepw_1d(misfdep(ji,jj  )  ) &
                           &                             - MIN( e3zps_min, e3t_1d(misfdep(ji,jj  )-1)*e3zps_rat )))
                     IF (zbathydiff <= zrisfdepdiff) THEN
                        mbathy (ji,jj+1) = mbathy(ji,jj+1) + 1
                        bathy  (ji,jj+1) = gdepw_1d(mbathy (ji,jj+1)  ) + MIN( e3zps_min, e3t_1d(mbathy (ji,jj+1)+1)*e3zps_rat )
                     ELSE
                        misfdep(ji,jj)   = misfdep(ji,jj) - 1
                        risfdep(ji,jj)   = gdepw_1d(misfdep(ji,jj  )+1) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj  )  )*e3zps_rat )
                     END IF
                  ELSE
                     misfdep(ji,jj)   = misfdep(ji,jj) - 1
                     risfdep(ji,jj)   = gdepw_1d(misfdep(ji,jj  )+1) - MIN( e3zps_min, e3t_1d(misfdep(ji,jj  )  )*e3zps_rat )
                  END IF
               ENDIF
            END DO
         END DO
 
 
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            misfdep(:,:) = INT( zbathy(:,:) )

            CALL lbc_lnk( risfdep,'T', 1. )
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:)  = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:)  = INT( zbathy(:,:) )
         ENDIF 
 
 ! point U mbathy(ji,jj) == misfdep(ji,jj+1) 
         DO jj = 1, jpjm1
            DO ji = 1, jpim1
               IF( misfdep(ji+1,jj) == mbathy(ji,jj) .AND. mbathy(ji,jj) > 1) THEN
                  IF ( .NOT. ln_iscpl ) THEN 
                  zbathydiff  =ABS(  bathy(ji  ,jj) - ( gdepw_1d(mbathy (ji,jj)+1) &
                       &                              + MIN( e3zps_min, e3t_1d(mbathy (ji  ,jj)+1)*e3zps_rat )))
                  zrisfdepdiff=ABS(risfdep(ji+1,jj) - ( gdepw_1d(misfdep(ji+1,jj)) &
                       &                              - MIN( e3zps_min, e3t_1d(misfdep(ji+1,jj)-1)*e3zps_rat )))
                  IF (zbathydiff <= zrisfdepdiff) THEN
                     mbathy(ji,jj) = mbathy(ji,jj) + 1
                     bathy(ji,jj)  = gdepw_1d(mbathy (ji,jj)) + MIN( e3zps_min, e3t_1d(mbathy(ji,jj) +1)*e3zps_rat )
                  ELSE
                     misfdep(ji+1,jj)= misfdep(ji+1,jj) - 1
                     risfdep(ji+1,jj) = gdepw_1d(misfdep(ji+1,jj)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji+1,jj))*e3zps_rat )
                  END IF
                  ELSE
                     misfdep(ji+1,jj)= misfdep(ji+1,jj) - 1
                     risfdep(ji+1,jj) = gdepw_1d(misfdep(ji+1,jj)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji+1,jj))*e3zps_rat )
                  ENDIF
               ENDIF
            ENDDO
         ENDDO
 
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            misfdep(:,:) = INT( zbathy(:,:) )

            CALL lbc_lnk( risfdep,'T', 1. )
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:)  = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:)  = INT( zbathy(:,:) )
         ENDIF 
 
 ! point U misfdep(ji,jj) == bathy(ji,jj+1) 
         DO jj = 1, jpjm1
            DO ji = 1, jpim1
               IF( misfdep(ji,jj) == mbathy(ji+1,jj) .AND. mbathy(ji,jj) > 1) THEN
                  IF ( .NOT. ln_iscpl ) THEN 
                     zbathydiff  =ABS(  bathy(ji+1,jj) - ( gdepw_1d(mbathy (ji+1,jj)+1) &
                          &                              + MIN( e3zps_min, e3t_1d(mbathy (ji+1,jj)+1)*e3zps_rat )))
                     zrisfdepdiff=ABS(risfdep(ji  ,jj) - ( gdepw_1d(misfdep(ji  ,jj)  ) &
                          &                              - MIN( e3zps_min, e3t_1d(misfdep(ji  ,jj)-1)*e3zps_rat )))
                     IF (zbathydiff <= zrisfdepdiff) THEN
                        mbathy(ji+1,jj)  = mbathy (ji+1,jj) + 1
                        bathy (ji+1,jj)  = gdepw_1d(mbathy (ji+1,jj)  ) + MIN( e3zps_min, e3t_1d(mbathy (ji+1,jj) +1)*e3zps_rat )
                     ELSE
                        misfdep(ji,jj)   = misfdep(ji  ,jj) - 1
                        risfdep(ji,jj)   = gdepw_1d(misfdep(ji  ,jj)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji  ,jj)   )*e3zps_rat )
                     END IF
                  ELSE
                     misfdep(ji,jj)   = misfdep(ji  ,jj) - 1
                     risfdep(ji,jj)   = gdepw_1d(misfdep(ji  ,jj)+1) - MIN( e3zps_min, e3t_1d(misfdep(ji  ,jj)   )*e3zps_rat )
                  ENDIF
               ENDIF
            ENDDO
         ENDDO
 
         IF( lk_mpp ) THEN
            zbathy(:,:)  = FLOAT( misfdep(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            misfdep(:,:) = INT( zbathy(:,:) )

            CALL lbc_lnk( risfdep,'T', 1. )
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:)  = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:)  = INT( zbathy(:,:) )
         ENDIF
      END DO
      ! end dig bathy/ice shelf to be compatible
      ! now fill single point in "coastline" of ice shelf, bathy, hole, and test again one cell tickness
      DO jl = 1,20
 
 ! remove single point "bay" on isf coast line in the ice shelf draft'
         DO jk = 2, jpk
            WHERE (misfdep==0) misfdep=jpk
            zmask=0._wp
            WHERE (misfdep <= jk) zmask=1
            DO jj = 2, jpjm1
               DO ji = 2, jpim1
                  IF (misfdep(ji,jj) == jk) THEN
                     ibtest = zmask(ji-1,jj) + zmask(ji+1,jj) + zmask(ji,jj-1) + zmask(ji,jj+1)
                     IF (ibtest <= 1) THEN
                        risfdep(ji,jj)=gdepw_1d(jk+1) ; misfdep(ji,jj)=jk+1
                        IF (misfdep(ji,jj) > mbathy(ji,jj)) misfdep(ji,jj) = jpk
                     END IF
                  END IF
               END DO
            END DO
         END DO
         WHERE (misfdep==jpk)
             misfdep=0 ; risfdep=0._wp ; mbathy=0 ; bathy=0._wp
         END WHERE
         IF( lk_mpp ) THEN
            zbathy(:,:)  = FLOAT( misfdep(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            misfdep(:,:) = INT( zbathy(:,:) )

            CALL lbc_lnk( risfdep,'T', 1. )
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:)  = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:)  = INT( zbathy(:,:) )
         ENDIF
 
 ! remove single point "bay" on bathy coast line beneath an ice shelf'
         DO jk = jpk,1,-1
            zmask=0._wp
            WHERE (mbathy >= jk ) zmask=1
            DO jj = 2, jpjm1
               DO ji = 2, jpim1
                  IF (mbathy(ji,jj) == jk .AND. misfdep(ji,jj) >= 2) THEN
                     ibtest = zmask(ji-1,jj) + zmask(ji+1,jj) + zmask(ji,jj-1) + zmask(ji,jj+1)
                     IF (ibtest <= 1) THEN
                        bathy(ji,jj)=gdepw_1d(jk) ; mbathy(ji,jj)=jk-1
                        IF (misfdep(ji,jj) > mbathy(ji,jj)) mbathy(ji,jj) = 0
                     END IF
                  END IF
               END DO
            END DO
         END DO
         WHERE (mbathy==0)
             misfdep=0 ; risfdep=0._wp ; mbathy=0 ; bathy=0._wp
         END WHERE
         IF( lk_mpp ) THEN
            zbathy(:,:)  = FLOAT( misfdep(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            misfdep(:,:) = INT( zbathy(:,:) )

            CALL lbc_lnk( risfdep,'T', 1. )
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:)  = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:)  = INT( zbathy(:,:) )
         ENDIF
 
 ! fill hole in ice shelf
         zmisfdep = misfdep
         zrisfdep = risfdep
         WHERE (zmisfdep <= 1._wp) zmisfdep=jpk
         DO jj = 2, jpjm1
            DO ji = 2, jpim1
               ibtestim1 = zmisfdep(ji-1,jj  ) ; ibtestip1 = zmisfdep(ji+1,jj  )
               ibtestjm1 = zmisfdep(ji  ,jj-1) ; ibtestjp1 = zmisfdep(ji  ,jj+1)
               IF( zmisfdep(ji,jj) >= mbathy(ji-1,jj  ) ) ibtestim1 = jpk
               IF( zmisfdep(ji,jj) >= mbathy(ji+1,jj  ) ) ibtestip1 = jpk
               IF( zmisfdep(ji,jj) >= mbathy(ji  ,jj-1) ) ibtestjm1 = jpk
               IF( zmisfdep(ji,jj) >= mbathy(ji  ,jj+1) ) ibtestjp1 = jpk
               ibtest=MIN(ibtestim1, ibtestip1, ibtestjm1, ibtestjp1)
               IF( ibtest == jpk .AND. misfdep(ji,jj) >= 2) THEN
                  mbathy(ji,jj) = 0 ; bathy(ji,jj) = 0.0_wp ; misfdep(ji,jj) = 0 ; risfdep(ji,jj) = 0.0_wp
               END IF
               IF( zmisfdep(ji,jj) < ibtest .AND. misfdep(ji,jj) >= 2) THEN
                  misfdep(ji,jj) = ibtest
                  risfdep(ji,jj) = gdepw_1d(ibtest)
               ENDIF
            ENDDO
         ENDDO
 
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) ) 
            CALL lbc_lnk( zbathy,  'T', 1. ) 
            misfdep(:,:) = INT( zbathy(:,:) ) 

            CALL lbc_lnk( risfdep, 'T', 1. ) 
            CALL lbc_lnk( bathy,   'T', 1. )

            zbathy(:,:) = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy,  'T', 1. )
            mbathy(:,:) = INT( zbathy(:,:) )
         ENDIF 
 !
 !! fill hole in bathymetry
         zmbathy (:,:)=mbathy (:,:)
         DO jj = 2, jpjm1
            DO ji = 2, jpim1
               ibtestim1 = zmbathy(ji-1,jj  ) ; ibtestip1 = zmbathy(ji+1,jj  )
               ibtestjm1 = zmbathy(ji  ,jj-1) ; ibtestjp1 = zmbathy(ji  ,jj+1)
               IF( zmbathy(ji,jj) <  misfdep(ji-1,jj  ) ) ibtestim1 = 0
               IF( zmbathy(ji,jj) <  misfdep(ji+1,jj  ) ) ibtestip1 = 0
               IF( zmbathy(ji,jj) <  misfdep(ji  ,jj-1) ) ibtestjm1 = 0
               IF( zmbathy(ji,jj) <  misfdep(ji  ,jj+1) ) ibtestjp1 = 0
               ibtest=MAX(ibtestim1, ibtestip1, ibtestjm1, ibtestjp1)
               IF( ibtest == 0 .AND. misfdep(ji,jj) >= 2) THEN
                  mbathy(ji,jj) = 0 ; bathy(ji,jj) = 0.0_wp ; misfdep(ji,jj) = 0 ; risfdep(ji,jj) = 0.0_wp ;
               END IF
               IF( ibtest < zmbathy(ji,jj) .AND. misfdep(ji,jj) >= 2) THEN
                  mbathy(ji,jj) = ibtest
                  bathy(ji,jj)  = gdepw_1d(ibtest+1) 
               ENDIF
            END DO
         END DO
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) ) 
            CALL lbc_lnk( zbathy,  'T', 1. ) 
            misfdep(:,:) = INT( zbathy(:,:) ) 

            CALL lbc_lnk( risfdep, 'T', 1. ) 
            CALL lbc_lnk( bathy,   'T', 1. )

            zbathy(:,:) = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy,  'T', 1. )
            mbathy(:,:) = INT( zbathy(:,:) )
         ENDIF 
 ! if not compatible after all check (ie U point water column less than 2 cells), mask U
         DO jj = 1, jpjm1
            DO ji = 1, jpim1
               IF (mbathy(ji,jj) == misfdep(ji+1,jj) .AND. mbathy(ji,jj) >= 1 .AND. mbathy(ji+1,jj) >= 1) THEN
                  mbathy(ji,jj)  = mbathy(ji,jj) - 1 ; bathy(ji,jj)   = gdepw_1d(mbathy(ji,jj)+1) ;
               END IF
            END DO
         END DO
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) ) 
            CALL lbc_lnk( zbathy,  'T', 1. ) 
            misfdep(:,:) = INT( zbathy(:,:) ) 

            CALL lbc_lnk( risfdep, 'T', 1. ) 
            CALL lbc_lnk( bathy,   'T', 1. )

            zbathy(:,:) = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy,  'T', 1. )
            mbathy(:,:) = INT( zbathy(:,:) )
         ENDIF 
 ! if not compatible after all check (ie U point water column less than 2 cells), mask U
         DO jj = 1, jpjm1
            DO ji = 1, jpim1
               IF (misfdep(ji,jj) == mbathy(ji+1,jj) .AND. mbathy(ji,jj) >= 1 .AND. mbathy(ji+1,jj) >= 1) THEN
                  mbathy(ji+1,jj)  = mbathy(ji+1,jj) - 1;   bathy(ji+1,jj)   = gdepw_1d(mbathy(ji+1,jj)+1) ;
               END IF
            END DO
         END DO
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) ) 
            CALL lbc_lnk( zbathy, 'T', 1. ) 
            misfdep(:,:) = INT( zbathy(:,:) ) 

            CALL lbc_lnk( risfdep,'T', 1. ) 
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:) = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:) = INT( zbathy(:,:) )
         ENDIF 
 ! if not compatible after all check (ie V point water column less than 2 cells), mask V
         DO jj = 1, jpjm1
            DO ji = 1, jpi
               IF (mbathy(ji,jj) == misfdep(ji,jj+1) .AND. mbathy(ji,jj) >= 1 .AND. mbathy(ji,jj+1) >= 1) THEN
                  mbathy(ji,jj)  = mbathy(ji,jj) - 1 ; bathy(ji,jj)   = gdepw_1d(mbathy(ji,jj)+1) ;
               END IF
            END DO
         END DO
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) ) 
            CALL lbc_lnk( zbathy, 'T', 1. ) 
            misfdep(:,:) = INT( zbathy(:,:) ) 

            CALL lbc_lnk( risfdep,'T', 1. ) 
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:) = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:) = INT( zbathy(:,:) )
         ENDIF 
 ! if not compatible after all check (ie V point water column less than 2 cells), mask V
         DO jj = 1, jpjm1
            DO ji = 1, jpi
               IF (misfdep(ji,jj) == mbathy(ji,jj+1) .AND. mbathy(ji,jj) >= 1 .AND. mbathy(ji,jj+1) >= 1) THEN
                  mbathy(ji,jj+1)  = mbathy(ji,jj+1) - 1 ; bathy(ji,jj+1) = gdepw_1d(mbathy(ji,jj+1)+1) ;
               END IF
            END DO
         END DO
         IF( lk_mpp ) THEN 
            zbathy(:,:)  = FLOAT( misfdep(:,:) ) 
            CALL lbc_lnk( zbathy, 'T', 1. ) 
            misfdep(:,:) = INT( zbathy(:,:) ) 

            CALL lbc_lnk( risfdep,'T', 1. ) 
            CALL lbc_lnk( bathy,  'T', 1. )

            zbathy(:,:) = FLOAT( mbathy(:,:) )
            CALL lbc_lnk( zbathy, 'T', 1. )
            mbathy(:,:) = INT( zbathy(:,:) )
         ENDIF 
 ! if not compatible after all check, mask T
         DO jj = 1, jpj
            DO ji = 1, jpi
               IF (mbathy(ji,jj) <= misfdep(ji,jj)) THEN
                  misfdep(ji,jj) = 0 ; risfdep(ji,jj) = 0._wp ; mbathy(ji,jj)  = 0 ; bathy(ji,jj)   = 0._wp ;
               END IF
            END DO
         END DO
 
         WHERE (mbathy(:,:) == 1)
            mbathy = 0; bathy = 0.0_wp ; misfdep = 0 ; risfdep = 0.0_wp
         END WHERE
      END DO 
! end check compatibility ice shelf/bathy
      ! remove very shallow ice shelf (less than ~ 10m if 75L)
      WHERE (risfdep(:,:) <= 10._wp)
         misfdep = 1; risfdep = 0.0_wp;
      END WHERE

      IF( icompt == 0 ) THEN 
         IF(lwp) WRITE(numout,*)'     no points with ice shelf too close to bathymetry' 
      ELSE 
         IF(lwp) WRITE(numout,*)'    ',icompt,' ocean grid points with ice shelf thickness reduced to avoid bathymetry' 
      ENDIF 

      ! compute scale factor and depth at T- and W- points
      DO jj = 1, jpj
         DO ji = 1, jpi
            ik = mbathy(ji,jj)
            IF( ik > 0 ) THEN               ! ocean point only
               ! max ocean level case
               IF( ik == jpkm1 ) THEN
                  zdepwp = bathy(ji,jj)
                  ze3tp  = bathy(ji,jj) - gdepw_1d(ik)
                  ze3wp = 0.5_wp * e3w_1d(ik) * ( 1._wp + ( ze3tp/e3t_1d(ik) ) )
                  e3t_0(ji,jj,ik  ) = ze3tp
                  e3t_0(ji,jj,ik+1) = ze3tp
                  e3w_0(ji,jj,ik  ) = ze3wp
                  e3w_0(ji,jj,ik+1) = ze3tp
                  gdepw_0(ji,jj,ik+1) = zdepwp
                  gdept_0(ji,jj,ik  ) = gdept_1d(ik-1) + ze3wp
                  gdept_0(ji,jj,ik+1) = gdept_0(ji,jj,ik) + ze3tp
                  !
               ELSE                         ! standard case
                  IF( bathy(ji,jj) <= gdepw_1d(ik+1) ) THEN  ;   gdepw_0(ji,jj,ik+1) = bathy(ji,jj)
                  ELSE                                       ;   gdepw_0(ji,jj,ik+1) = gdepw_1d(ik+1)
                  ENDIF
      !            gdepw_0(ji,jj,ik+1) = gdepw_1d(ik+1)
!gm Bug?  check the gdepw_1d
                  !       ... on ik
                  gdept_0(ji,jj,ik) = gdepw_1d(ik) + ( gdepw_0(ji,jj,ik+1) - gdepw_1d(ik) )   &
                     &                             * ((gdept_1d(     ik  ) - gdepw_1d(ik) )   &
                     &                             / ( gdepw_1d(     ik+1) - gdepw_1d(ik) ))
                  e3t_0  (ji,jj,ik  ) = gdepw_0(ji,jj,ik+1) - gdepw_1d(ik  )
                  e3w_0  (ji,jj,ik  ) = gdept_0(ji,jj,ik  ) - gdept_1d(ik-1)
                  !       ... on ik+1
                  e3w_0  (ji,jj,ik+1) = e3t_0  (ji,jj,ik)
                  e3t_0  (ji,jj,ik+1) = e3t_0  (ji,jj,ik)
               ENDIF
            ENDIF
         END DO
      END DO
      !
      it = 0
      DO jj = 1, jpj
         DO ji = 1, jpi
            ik = mbathy(ji,jj)
            IF( ik > 0 ) THEN               ! ocean point only
               e3tp (ji,jj) = e3t_0(ji,jj,ik)
               e3wp (ji,jj) = e3w_0(ji,jj,ik)
               ! test
               zdiff= gdepw_0(ji,jj,ik+1) - gdept_0(ji,jj,ik  )
               IF( zdiff <= 0._wp .AND. lwp ) THEN 
                  it = it + 1
                  WRITE(numout,*) ' it      = ', it, ' ik      = ', ik, ' (i,j) = ', ji, jj
                  WRITE(numout,*) ' bathy = ', bathy(ji,jj)
                  WRITE(numout,*) ' gdept_0 = ', gdept_0(ji,jj,ik), ' gdepw_0 = ', gdepw_0(ji,jj,ik+1), ' zdiff = ', zdiff
                  WRITE(numout,*) ' e3tp    = ', e3t_0  (ji,jj,ik), ' e3wp    = ', e3w_0  (ji,jj,ik  )
               ENDIF
            ENDIF
         END DO
      END DO
      !
      ! (ISF) Definition of e3t, u, v, w for ISF case
      DO jj = 1, jpj 
         DO ji = 1, jpi 
            ik = misfdep(ji,jj) 
            IF( ik > 1 ) THEN               ! ice shelf point only 
               IF( risfdep(ji,jj) < gdepw_1d(ik) )  risfdep(ji,jj)= gdepw_1d(ik) 
               gdepw_0(ji,jj,ik) = risfdep(ji,jj) 
!gm Bug?  check the gdepw_0 
            !       ... on ik 
               gdept_0(ji,jj,ik) = gdepw_1d(ik+1) - ( gdepw_1d(ik+1) - gdepw_0(ji,jj,ik) )   & 
                  &                               * ( gdepw_1d(ik+1) - gdept_1d(ik)      )   & 
                  &                               / ( gdepw_1d(ik+1) - gdepw_1d(ik)      ) 
               e3t_0  (ji,jj,ik  ) = gdepw_1d(ik+1) - gdepw_0(ji,jj,ik) 
               e3w_0  (ji,jj,ik+1) = gdept_1d(ik+1) - gdept_0(ji,jj,ik)

               IF( ik + 1 == mbathy(ji,jj) ) THEN               ! ice shelf point only (2 cell water column) 
                  e3w_0  (ji,jj,ik+1) = gdept_0(ji,jj,ik+1) - gdept_0(ji,jj,ik) 
               ENDIF 
            !       ... on ik / ik-1 
               e3w_0  (ji,jj,ik  ) = e3t_0  (ji,jj,ik) !2._wp * (gdept_0(ji,jj,ik) - gdepw_0(ji,jj,ik)) 
               gdept_0(ji,jj,ik-1) = gdept_0(ji,jj,ik) - e3w_0(ji,jj,ik)
               e3t_0  (ji,jj,ik-1) = gdepw_0(ji,jj,ik) - gdepw_1d(ik-1)
               e3w_0  (ji,jj,ik-1) = gdept_0(ji,jj,ik-1) - gdept_1d(ik-2)
               gdepw_0(ji,jj,ik-1) = gdepw_0(ji,jj,ik) - e3t_0(ji,jj,ik-1)
            ENDIF 
         END DO 
      END DO 
   
      it = 0 
      DO jj = 1, jpj 
         DO ji = 1, jpi 
            ik = misfdep(ji,jj) 
            IF( ik > 1 ) THEN               ! ice shelf point only 
               e3tp (ji,jj) = e3t_0(ji,jj,ik  ) 
               e3wp (ji,jj) = e3w_0(ji,jj,ik+1 ) 
            ! test 
               zdiff= gdept_0(ji,jj,ik) - gdepw_0(ji,jj,ik  ) 
               IF( zdiff <= 0. .AND. lwp ) THEN  
                  it = it + 1 
                  WRITE(numout,*) ' it      = ', it, ' ik      = ', ik, ' (i,j) = ', ji, jj 
                  WRITE(numout,*) ' risfdep = ', risfdep(ji,jj) 
                  WRITE(numout,*) ' gdept = ', gdept_0(ji,jj,ik), ' gdepw = ', gdepw_0(ji,jj,ik+1), ' zdiff = ', zdiff 
                  WRITE(numout,*) ' e3tp  = ', e3tp(ji,jj), ' e3wp  = ', e3wp(ji,jj) 
               ENDIF 
            ENDIF 
         END DO 
      END DO 

      CALL wrk_dealloc( jpi, jpj, zmask, zbathy, zrisfdep )
      CALL wrk_dealloc( jpi, jpj, zmisfdep, zmbathy )
      !
      IF( nn_timing == 1 )   CALL timing_stop('zgr_isf')
      !      
   END SUBROUTINE zgr_isf


   SUBROUTINE zgr_sco
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE zgr_sco  ***
      !!                     
      !! ** Purpose :   define the s-coordinate system
      !!
      !! ** Method  :   s-coordinate
      !!         The depth of model levels is defined as the product of an
      !!      analytical function by the local bathymetry, while the vertical
      !!      scale factors are defined as the product of the first derivative
      !!      of the analytical function by the bathymetry.
      !!      (this solution save memory as depth and scale factors are not
      !!      3d fields)
      !!          - Read bathymetry (in meters) at t-point and compute the
      !!         bathymetry at u-, v-, and f-points.
      !!            hbatu = mi( hbatt )
      !!            hbatv = mj( hbatt )
      !!            hbatf = mi( mj( hbatt ) )
      !!          - Compute z_gsigt, z_gsigw, z_esigt, z_esigw from an analytical
      !!         function and its derivative given as function.
      !!            z_gsigt(k) = fssig (k    )
      !!            z_gsigw(k) = fssig (k-0.5)
      !!            z_esigt(k) = fsdsig(k    )
      !!            z_esigw(k) = fsdsig(k-0.5)
      !!      Three options for stretching are give, and they can be modified
      !!      following the users requirements. Nevertheless, the output as
      !!      well as the way to compute the model levels and scale factors
      !!      must be respected in order to insure second order accuracy
      !!      schemes.
      !!
      !!      The three methods for stretching available are:
      !! 
      !!           s_sh94 (Song and Haidvogel 1994)
      !!                a sinh/tanh function that allows sigma and stretched sigma
      !!
      !!           s_sf12 (Siddorn and Furner 2012?)
      !!                allows the maintenance of fixed surface and or
      !!                bottom cell resolutions (cf. geopotential coordinates) 
      !!                within an analytically derived stretched S-coordinate framework.
      !! 
      !!          s_tanh  (Madec et al 1996)
      !!                a cosh/tanh function that gives stretched coordinates        
      !!
      !!----------------------------------------------------------------------
      INTEGER  ::   ji, jj, jk, jl           ! dummy loop argument
      INTEGER  ::   iip1, ijp1, iim1, ijm1   ! temporary integers
      INTEGER  ::   ios                      ! Local integer output status for namelist read
      REAL(wp) ::   zrmax, ztaper   ! temporary scalars
      REAL(wp) ::   zrfact
      !
      REAL(wp), POINTER, DIMENSION(:,:  ) :: ztmpi1, ztmpi2, ztmpj1, ztmpj2
      REAL(wp), POINTER, DIMENSION(:,:  ) :: zenv, ztmp, zmsk, zri, zrj, zhbat
      !!
      NAMELIST/namzgr_sco/ln_s_sh94, ln_s_sf12, ln_sigcrit, rn_sbot_min, rn_sbot_max, rn_hc, rn_rmax,rn_theta, &
         &                rn_thetb, rn_bb, rn_alpha, rn_efold, rn_zs, rn_zb_a, rn_zb_b
     !!----------------------------------------------------------------------
      !
      IF( nn_timing == 1 )  CALL timing_start('zgr_sco')
      !
      CALL wrk_alloc( jpi,jpj,   zenv, ztmp, zmsk, zri, zrj, zhbat , ztmpi1, ztmpi2, ztmpj1, ztmpj2 )
      !
      REWIND( numnam_ref )              ! Namelist namzgr_sco in reference namelist : Sigma-stretching parameters
      READ  ( numnam_ref, namzgr_sco, IOSTAT = ios, ERR = 901)
901   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namzgr_sco in reference namelist', lwp )

      REWIND( numnam_cfg )              ! Namelist namzgr_sco in configuration namelist : Sigma-stretching parameters
      READ  ( numnam_cfg, namzgr_sco, IOSTAT = ios, ERR = 902 )
902   IF( ios /= 0 ) CALL ctl_nam ( ios , 'namzgr_sco in configuration namelist', lwp )
      IF(lwm) WRITE ( numond, namzgr_sco )
      
      rn_hc = rn_hc + rn_wd_ref_depth

      IF(lwp) THEN                           ! control print
         WRITE(numout,*)
         WRITE(numout,*) 'domzgr_sco : s-coordinate or hybrid z-s-coordinate'
         WRITE(numout,*) '~~~~~~~~~~~'
         WRITE(numout,*) '   Namelist namzgr_sco'
         WRITE(numout,*) '     stretching coeffs '
         WRITE(numout,*) '        maximum depth of s-bottom surface (>0)       rn_sbot_max   = ',rn_sbot_max
         WRITE(numout,*) '        minimum depth of s-bottom surface (>0)       rn_sbot_min   = ',rn_sbot_min
         WRITE(numout,*) '        Critical depth                               rn_hc         = ',rn_hc
         WRITE(numout,*) '        maximum cut-off r-value allowed              rn_rmax       = ',rn_rmax
         WRITE(numout,*) '     Song and Haidvogel 1994 stretching              ln_s_sh94     = ',ln_s_sh94
         WRITE(numout,*) '        Song and Haidvogel 1994 stretching coefficients'
         WRITE(numout,*) '        surface control parameter (0<=rn_theta<=20)  rn_theta      = ',rn_theta
         WRITE(numout,*) '        bottom  control parameter (0<=rn_thetb<= 1)  rn_thetb      = ',rn_thetb
         WRITE(numout,*) '        stretching parameter (song and haidvogel)    rn_bb         = ',rn_bb
         WRITE(numout,*) '     Siddorn and Furner 2012 stretching              ln_s_sf12     = ',ln_s_sf12
         WRITE(numout,*) '        switching to sigma (T) or Z (F) at H<Hc      ln_sigcrit    = ',ln_sigcrit
         WRITE(numout,*) '        Siddorn and Furner 2012 stretching coefficients'
         WRITE(numout,*) '        stretchin parameter ( >1 surface; <1 bottom) rn_alpha      = ',rn_alpha
         WRITE(numout,*) '        e-fold length scale for transition region    rn_efold      = ',rn_efold
         WRITE(numout,*) '        Surface cell depth (Zs) (m)                  rn_zs         = ',rn_zs
         WRITE(numout,*) '        Bathymetry multiplier for Zb                 rn_zb_a       = ',rn_zb_a
         WRITE(numout,*) '        Offset for Zb                                rn_zb_b       = ',rn_zb_b
         WRITE(numout,*) '        Bottom cell (Zb) (m) = H*rn_zb_a + rn_zb_b'
      ENDIF

      ! CEOD
      ! Add on some reference level to make negative bathy positive to create sensible e3t_0's
      ! CEOD MAKE points on the perimeter assuming a bondary is here on shallower than
      ! 10m so that tide can be specified here.
      if(1==1) then !CEOD BDY CASE
      DO jj = 1, jpj
         DO ji = 1, jpi
            !CEODIF( mig(ji) <= 2 .or. mjg(jj) <= 2  .or. mig(ji) >= jpiglo-2 .or.  mjg(jj) >=jpjglo-2) then
            IF( mig(ji) <= 9   .or. mjg(jj) <= 9 .or.  mjg(jj) >=jpjglo-9) then
               IF( bathy(ji,jj) > 0.0)   then
                  bathy(ji,jj) = max(10.0,bathy(ji,jj)) !
               ENDIF
            ENDIF
         END DO
      END DO
       endif !CEOD END BDY CAE
      bathy(:,:) = bathy(:,:) + rn_wd_ref_depth !  Arbitrary reference level, This needs
                                      !  to be accounted for in istate in the actual model and bdys etc.


      hift(:,:) = rn_sbot_min                     ! set the minimum depth for the s-coordinate
      hifu(:,:) = rn_sbot_min
      hifv(:,:) = rn_sbot_min
      hiff(:,:) = rn_sbot_min

      !                                        ! set maximum ocean depth
      bathy(:,:) = MIN( rn_sbot_max, bathy(:,:) )

         DO jj = 1, jpj
            DO ji = 1, jpi
              IF( bathy(ji,jj) > 0._wp )   bathy(ji,jj) = MAX( rn_sbot_min, bathy(ji,jj) )
            END DO
         END DO
      !                                        ! =============================
      !                                        ! Define the envelop bathymetry   (hbatt)
      !                                        ! =============================
      ! use r-value to create hybrid coordinates
      zenv(:,:) = bathy(:,:)
      !
      ! set first land point adjacent to a wet cell to sbot_min as this needs to be included in smoothing
         DO jj = 1, jpj
            DO ji = 1, jpi
               IF( bathy(ji,jj) == 0._wp ) THEN
                  iip1 = MIN( ji+1, jpi )
                  ijp1 = MIN( jj+1, jpj )
                  iim1 = MAX( ji-1, 1 )
                  ijm1 = MAX( jj-1, 1 )
!!DB to reproduce R&D suite
                  IF( ( + bathy(iim1,ijp1) + bathy(ji,ijp1) + bathy(iip1,ijp1)              &
                     &  + bathy(iim1,jj  )                  + bathy(iip1,jj  )              &
                     &  + bathy(iim1,ijm1) + bathy(ji,ijm1) + bathy(iip1,ijp1)  ) > 0._wp ) &
                     &    zenv(ji,jj) = rn_sbot_min
!!gm
!!gm               IF( ( bathy(iip1,jj  ) + bathy(iim1,jj  ) + bathy(ji,ijp1  ) + bathy(ji,ijm1) +         &
!!gm                  &  bathy(iip1,ijp1) + bathy(iim1,ijm1) + bathy(iip1,ijp1) + bathy(iim1,ijm1)) > 0._wp ) THEN
!!gm               zenv(ji,jj) = rn_sbot_min
!!gm             ENDIF
!!gm end
              ENDIF
            END DO
         END DO

      ! apply lateral boundary condition   CAUTION: keep the value when the lbc field is zero
      CALL lbc_lnk( zenv, 'T', 1._wp, 'no0' )
      ! 
      ! smooth the bathymetry (if required)
      scosrf(:,:) = 0._wp             ! ocean surface depth (here zero: no under ice-shelf sea)
      scobot(:,:) = bathy(:,:)        ! ocean bottom  depth
      !
      jl = 0
      zrmax = 1._wp
      !   
      !     
      ! set scaling factor used in reducing vertical gradients
      zrfact = ( 1._wp - rn_rmax ) / ( 1._wp + rn_rmax )
      !
      ! initialise temporary evelope depth arrays
      ztmpi1(:,:) = zenv(:,:)
      ztmpi2(:,:) = zenv(:,:)
      ztmpj1(:,:) = zenv(:,:)
      ztmpj2(:,:) = zenv(:,:)
      !
      ! initialise temporary r-value arrays
      zri(:,:) = 1._wp
      zrj(:,:) = 1._wp
      !                                                            ! ================ !
      DO WHILE( jl <= 10000 .AND. ( zrmax - rn_rmax ) > 1.e-8_wp ) !  Iterative loop  !
         !                                                         ! ================ !
         jl = jl + 1
         zrmax = 0._wp
         ! we set zrmax from previous r-values (zri and zrj) first
         ! if set after current r-value calculation (as previously)
         ! we could exit DO WHILE prematurely before checking r-value
         ! of current zenv
         DO jj = 1, nlcj
            DO ji = 1, nlci
               zrmax = MAX( zrmax, ABS(zri(ji,jj)), ABS(zrj(ji,jj)) )
            END DO
         END DO
         zri(:,:) = 0._wp
         zrj(:,:) = 0._wp
         DO jj = 1, nlcj
            DO ji = 1, nlci
               iip1 = MIN( ji+1, nlci )      ! force zri = 0 on last line (ji=ncli+1 to jpi)
               ijp1 = MIN( jj+1, nlcj )      ! force zrj = 0 on last raw  (jj=nclj+1 to jpj)
               IF( (zenv(ji,jj) > 0._wp) .AND. (zenv(iip1,jj) > 0._wp)) THEN
                  zri(ji,jj) = ( zenv(iip1,jj  ) - zenv(ji,jj) ) / ( zenv(iip1,jj  ) + zenv(ji,jj) )
               END IF
               IF( (zenv(ji,jj) > 0._wp) .AND. (zenv(ji,ijp1) > 0._wp)) THEN
                  zrj(ji,jj) = ( zenv(ji  ,ijp1) - zenv(ji,jj) ) / ( zenv(ji  ,ijp1) + zenv(ji,jj) )
               END IF
               IF( zri(ji,jj) >  rn_rmax )   ztmpi1(ji  ,jj  ) = zenv(iip1,jj  ) * zrfact
               IF( zri(ji,jj) < -rn_rmax )   ztmpi2(iip1,jj  ) = zenv(ji  ,jj  ) * zrfact
               IF( zrj(ji,jj) >  rn_rmax )   ztmpj1(ji  ,jj  ) = zenv(ji  ,ijp1) * zrfact
               IF( zrj(ji,jj) < -rn_rmax )   ztmpj2(ji  ,ijp1) = zenv(ji  ,jj  ) * zrfact
            END DO
         END DO
         IF( lk_mpp )   CALL mpp_max( zrmax )   ! max over the global domain
         !
         IF(lwp)WRITE(numout,*) 'zgr_sco :   iter= ',jl, ' rmax= ', zrmax
         !
         DO jj = 1, nlcj
            DO ji = 1, nlci
               zenv(ji,jj) = MAX(zenv(ji,jj), ztmpi1(ji,jj), ztmpi2(ji,jj), ztmpj1(ji,jj), ztmpj2(ji,jj) )
            END DO
         END DO
         ! apply lateral boundary condition   CAUTION: keep the value when the lbc field is zero
         CALL lbc_lnk( zenv, 'T', 1._wp, 'no0' )
         !                                                  ! ================ !
      END DO                                                !     End loop     !
      !                                                     ! ================ !
      DO jj = 1, jpj
         DO ji = 1, jpi
            zenv(ji,jj) = MAX( zenv(ji,jj), rn_sbot_min ) ! set all points to avoid undefined scale value warnings
         END DO
      END DO
      !
      ! Envelope bathymetry saved in hbatt
      hbatt(:,:) = zenv(:,:) 
      IF( MINVAL( gphit(:,:) ) * MAXVAL( gphit(:,:) ) <= 0._wp ) THEN
         CALL ctl_warn( ' s-coordinates are tapered in vicinity of the Equator' )
         DO jj = 1, jpj
            DO ji = 1, jpi
               ztaper = EXP( -(gphit(ji,jj)/8._wp)**2._wp )
               hbatt(ji,jj) = rn_sbot_max * ztaper + hbatt(ji,jj) * ( 1._wp - ztaper )
            END DO
         END DO
      ENDIF
      !
      !                                        ! ==============================
      !                                        !   hbatu, hbatv, hbatf fields
      !                                        ! ==============================
      IF(lwp) THEN
         WRITE(numout,*)
           WRITE(numout,*) ' zgr_sco: minimum depth of the envelop topography set to : ', rn_sbot_min
      ENDIF
      hbatu(:,:) = rn_sbot_min
      hbatv(:,:) = rn_sbot_min
      hbatf(:,:) = rn_sbot_min
      DO jj = 1, jpjm1
        DO ji = 1, jpim1   ! NO vector opt.
           hbatu(ji,jj) = 0.50_wp * ( hbatt(ji  ,jj) + hbatt(ji+1,jj  ) )
           hbatv(ji,jj) = 0.50_wp * ( hbatt(ji  ,jj) + hbatt(ji  ,jj+1) )
           hbatf(ji,jj) = 0.25_wp * ( hbatt(ji  ,jj) + hbatt(ji  ,jj+1)   &
              &                     + hbatt(ji+1,jj) + hbatt(ji+1,jj+1) )
        END DO
      END DO

      ! 
      ! Apply lateral boundary condition
!!gm  ! CAUTION: retain non zero value in the initial file this should be OK for orca cfg, not for EEL
      zhbat(:,:) = hbatu(:,:)   ;   CALL lbc_lnk( hbatu, 'U', 1._wp )
      DO jj = 1, jpj
         DO ji = 1, jpi
            IF( hbatu(ji,jj) == 0._wp ) THEN
               !No worries about the following line when ln_wd == .true.
               IF( zhbat(ji,jj) == 0._wp )   hbatu(ji,jj) = rn_sbot_min
               IF( zhbat(ji,jj) /= 0._wp )   hbatu(ji,jj) = zhbat(ji,jj)
            ENDIF
         END DO
      END DO
      zhbat(:,:) = hbatv(:,:)   ;   CALL lbc_lnk( hbatv, 'V', 1._wp )
      DO jj = 1, jpj
         DO ji = 1, jpi
            IF( hbatv(ji,jj) == 0._wp ) THEN
               IF( zhbat(ji,jj) == 0._wp )   hbatv(ji,jj) = rn_sbot_min
               IF( zhbat(ji,jj) /= 0._wp )   hbatv(ji,jj) = zhbat(ji,jj)
            ENDIF
         END DO
      END DO
      zhbat(:,:) = hbatf(:,:)   ;   CALL lbc_lnk( hbatf, 'F', 1._wp )
      DO jj = 1, jpj
         DO ji = 1, jpi
            IF( hbatf(ji,jj) == 0._wp ) THEN
               IF( zhbat(ji,jj) == 0._wp )   hbatf(ji,jj) = rn_sbot_min
               IF( zhbat(ji,jj) /= 0._wp )   hbatf(ji,jj) = zhbat(ji,jj)
            ENDIF
         END DO
      END DO

!!bug:  key_helsinki a verifer
        hift(:,:) = MIN( hift(:,:), hbatt(:,:) )
        hifu(:,:) = MIN( hifu(:,:), hbatu(:,:) )
        hifv(:,:) = MIN( hifv(:,:), hbatv(:,:) )
        hiff(:,:) = MIN( hiff(:,:), hbatf(:,:) )

      IF( nprint == 1 .AND. lwp )   THEN
         WRITE(numout,*) ' MAX val hif   t ', MAXVAL( hift (:,:) ), ' f ', MAXVAL( hiff (:,:) ),  &
            &                        ' u ',   MAXVAL( hifu (:,:) ), ' v ', MAXVAL( hifv (:,:) )
         WRITE(numout,*) ' MIN val hif   t ', MINVAL( hift (:,:) ), ' f ', MINVAL( hiff (:,:) ),  &
            &                        ' u ',   MINVAL( hifu (:,:) ), ' v ', MINVAL( hifv (:,:) )
         WRITE(numout,*) ' MAX val hbat  t ', MAXVAL( hbatt(:,:) ), ' f ', MAXVAL( hbatf(:,:) ),  &
            &                        ' u ',   MAXVAL( hbatu(:,:) ), ' v ', MAXVAL( hbatv(:,:) )
         WRITE(numout,*) ' MIN val hbat  t ', MINVAL( hbatt(:,:) ), ' f ', MINVAL( hbatf(:,:) ),  &
            &                        ' u ',   MINVAL( hbatu(:,:) ), ' v ', MINVAL( hbatv(:,:) )
      ENDIF
!! helsinki

      !                                            ! =======================
      !                                            !   s-ccordinate fields     (gdep., e3.)
      !                                            ! =======================
      !
      ! non-dimensional "sigma" for model level depth at w- and t-levels


!========================================================================
! Song and Haidvogel  1994 (ln_s_sh94=T)
! Siddorn and Furner 2012 (ln_sf12=T)
! or  tanh function       (both false)                    
!========================================================================
      IF      ( ln_s_sh94 ) THEN 
                           CALL s_sh94()
      ELSE IF ( ln_s_sf12 ) THEN
                           CALL s_sf12()
      ELSE                 
                           CALL s_tanh()
      ENDIF 

      CALL lbc_lnk( e3t_0 , 'T', 1._wp )
      CALL lbc_lnk( e3u_0 , 'U', 1._wp )
      CALL lbc_lnk( e3v_0 , 'V', 1._wp )
      CALL lbc_lnk( e3f_0 , 'F', 1._wp )
      CALL lbc_lnk( e3w_0 , 'W', 1._wp )
      CALL lbc_lnk( e3uw_0, 'U', 1._wp )
      CALL lbc_lnk( e3vw_0, 'V', 1._wp )
      !
        WHERE( e3t_0 (:,:,:) == 0._wp )   e3t_0 (:,:,:) = 1._wp
        WHERE( e3u_0 (:,:,:) == 0._wp )   e3u_0 (:,:,:) = 1._wp
        WHERE( e3v_0 (:,:,:) == 0._wp )   e3v_0 (:,:,:) = 1._wp
        WHERE( e3f_0 (:,:,:) == 0._wp )   e3f_0 (:,:,:) = 1._wp
        WHERE( e3w_0 (:,:,:) == 0._wp )   e3w_0 (:,:,:) = 1._wp
        WHERE( e3uw_0(:,:,:) == 0._wp )   e3uw_0(:,:,:) = 1._wp
        WHERE( e3vw_0(:,:,:) == 0._wp )   e3vw_0(:,:,:) = 1._wp


!!gm   I don't like that HERE we are supposed to set the reference coordinate (i.e. _0 arrays)
!!gm   and only that !!!!!
!!gm   THIS should be removed from here !
      gdept_n(:,:,:) = gdept_0(:,:,:)
      gdepw_n(:,:,:) = gdepw_0(:,:,:)
      gde3w_n(:,:,:) = gde3w_0(:,:,:)
      e3t_n  (:,:,:) = e3t_0  (:,:,:)
      e3u_n  (:,:,:) = e3u_0  (:,:,:)
      e3v_n  (:,:,:) = e3v_0  (:,:,:)
      e3f_n  (:,:,:) = e3f_0  (:,:,:)
      e3w_n  (:,:,:) = e3w_0  (:,:,:)
      e3uw_n (:,:,:) = e3uw_0 (:,:,:)
      e3vw_n (:,:,:) = e3vw_0 (:,:,:)
!!gm and obviously in the following, use the _0 arrays until the end of this subroutine
!! gm end
!!
      ! HYBRID : 
      DO jj = 1, jpj
         DO ji = 1, jpi
            DO jk = 1, jpkm1
               IF( scobot(ji,jj) >= gdept_n(ji,jj,jk) )   mbathy(ji,jj) = MAX( 2, jk )
            END DO
         END DO
      END DO
      IF( nprint == 1 .AND. lwp ) WRITE(numout,*) ' MIN val mbathy h90 ', MINVAL( mbathy(:,:) ),   &
         &                                                       ' MAX ', MAXVAL( mbathy(:,:) )

      IF( nprint == 1  .AND. lwp )   THEN         ! min max values over the local domain
         WRITE(numout,*) ' MIN val mbathy  ', MINVAL( mbathy(:,:)    ), ' MAX ', MAXVAL( mbathy(:,:) )
         WRITE(numout,*) ' MIN val depth t ', MINVAL( gdept_0(:,:,:) ),   &
            &                          ' w ', MINVAL( gdepw_0(:,:,:) ), '3w '  , MINVAL( gde3w_0(:,:,:) )
         WRITE(numout,*) ' MIN val e3    t ', MINVAL( e3t_0  (:,:,:) ), ' f '  , MINVAL( e3f_0  (:,:,:) ),   &
            &                          ' u ', MINVAL( e3u_0  (:,:,:) ), ' u '  , MINVAL( e3v_0  (:,:,:) ),   &
            &                          ' uw', MINVAL( e3uw_0 (:,:,:) ), ' vw'  , MINVAL( e3vw_0 (:,:,:) ),   &
            &                          ' w ', MINVAL( e3w_0  (:,:,:) )

         WRITE(numout,*) ' MAX val depth t ', MAXVAL( gdept_0(:,:,:) ),   &
            &                          ' w ', MAXVAL( gdepw_0(:,:,:) ), '3w '  , MAXVAL( gde3w_0(:,:,:) )
         WRITE(numout,*) ' MAX val e3    t ', MAXVAL( e3t_0  (:,:,:) ), ' f '  , MAXVAL( e3f_0  (:,:,:) ),   &
            &                          ' u ', MAXVAL( e3u_0  (:,:,:) ), ' u '  , MAXVAL( e3v_0  (:,:,:) ),   &
            &                          ' uw', MAXVAL( e3uw_0 (:,:,:) ), ' vw'  , MAXVAL( e3vw_0 (:,:,:) ),   &
            &                          ' w ', MAXVAL( e3w_0  (:,:,:) )
      ENDIF
      !  END DO
      IF(lwp) THEN                                  ! selected vertical profiles
         WRITE(numout,*)
         WRITE(numout,*) ' domzgr: vertical coordinates : point (1,1,k) bathy = ', bathy(1,1), hbatt(1,1)
         WRITE(numout,*) ' ~~~~~~  --------------------'
         WRITE(numout,"(9x,' level  gdept_0   gdepw_0   e3t_0    e3w_0')")
         WRITE(numout,"(10x,i4,4f9.2)") ( jk, gdept_0(1,1,jk), gdepw_0(1,1,jk),     &
            &                                 e3t_0 (1,1,jk) , e3w_0 (1,1,jk) , jk=1,jpk )
         DO jj = mj0(20), mj1(20)
            DO ji = mi0(20), mi1(20)
               WRITE(numout,*)
               WRITE(numout,*) ' domzgr: vertical coordinates : point (20,20,k)   bathy = ', bathy(ji,jj), hbatt(ji,jj)
               WRITE(numout,*) ' ~~~~~~  --------------------'
               WRITE(numout,"(9x,' level  gdept_0   gdepw_0   e3t_0    e3w_0')")
               WRITE(numout,"(10x,i4,4f9.2)") ( jk, gdept_0(ji,jj,jk), gdepw_0(ji,jj,jk),     &
                  &                                 e3t_0 (ji,jj,jk) , e3w_0 (ji,jj,jk) , jk=1,jpk )
            END DO
         END DO
         DO jj = mj0(74), mj1(74)
            DO ji = mi0(100), mi1(100)
               WRITE(numout,*)
               WRITE(numout,*) ' domzgr: vertical coordinates : point (100,74,k)   bathy = ', bathy(ji,jj), hbatt(ji,jj)
               WRITE(numout,*) ' ~~~~~~  --------------------'
               WRITE(numout,"(9x,' level  gdept_0   gdepw_0   e3t_0    e3w_0')")
               WRITE(numout,"(10x,i4,4f9.2)") ( jk, gdept_0(ji,jj,jk), gdepw_0(ji,jj,jk),     &
                  &                                 e3t_0 (ji,jj,jk) , e3w_0 (ji,jj,jk) , jk=1,jpk )
            END DO
         END DO
      ENDIF
      !
      !================================================================================
      ! check the coordinate makes sense
      !================================================================================
      DO ji = 1, jpi
         DO jj = 1, jpj
            !
            IF( hbatt(ji,jj) > 0._wp) THEN
               DO jk = 1, mbathy(ji,jj)
                 ! check coordinate is monotonically increasing
                 IF (e3w_n(ji,jj,jk) <= 0._wp .OR. e3t_n(ji,jj,jk) <= 0._wp ) THEN
                    WRITE(ctmp1,*) 'ERROR zgr_sco :   e3w   or e3t   =< 0  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'ERROR zgr_sco :   e3w   or e3t   =< 0  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'e3w',e3w_n(ji,jj,:)
                    WRITE(numout,*) 'e3t',e3t_n(ji,jj,:)
                    CALL ctl_stop( ctmp1 )
                 ENDIF
                 ! and check it has never gone negative
                 IF( gdepw_n(ji,jj,jk) < 0._wp .OR. gdept_n(ji,jj,jk) < 0._wp ) THEN
                    WRITE(ctmp1,*) 'ERROR zgr_sco :   gdepw or gdept =< 0  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'ERROR zgr_sco :   gdepw   or gdept   =< 0  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'gdepw',gdepw_n(ji,jj,:)
                    WRITE(numout,*) 'gdept',gdept_n(ji,jj,:)
                    CALL ctl_stop( ctmp1 )
                 ENDIF
                 ! and check it never exceeds the total depth
                 IF( gdepw_n(ji,jj,jk) > hbatt(ji,jj) ) THEN
                    WRITE(ctmp1,*) 'ERROR zgr_sco :   gdepw > hbatt  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'ERROR zgr_sco :   gdepw > hbatt  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'gdepw',gdepw_n(ji,jj,:)
                    CALL ctl_stop( ctmp1 )
                 ENDIF
               END DO
               !
               DO jk = 1, mbathy(ji,jj)-1
                 ! and check it never exceeds the total depth
                IF( gdept_n(ji,jj,jk) > hbatt(ji,jj) ) THEN
                    WRITE(ctmp1,*) 'ERROR zgr_sco :   gdept > hbatt  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'ERROR zgr_sco :   gdept > hbatt  at point (i,j,k)= ', ji, jj, jk
                    WRITE(numout,*) 'gdept',gdept_n(ji,jj,:)
                    CALL ctl_stop( ctmp1 )
                 ENDIF
               END DO
            ENDIF
         END DO
      END DO
      !
      CALL wrk_dealloc( jpi, jpj, zenv, ztmp, zmsk, zri, zrj, zhbat , ztmpi1, ztmpi2, ztmpj1, ztmpj2 )
      !
      IF( nn_timing == 1 )  CALL timing_stop('zgr_sco')
      !
   END SUBROUTINE zgr_sco


   SUBROUTINE s_sh94()
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE s_sh94  ***
      !!                     
      !! ** Purpose :   stretch the s-coordinate system
      !!
      !! ** Method  :   s-coordinate stretch using the Song and Haidvogel 1994
      !!                mixed S/sigma coordinate
      !!
      !! Reference : Song and Haidvogel 1994. 
      !!----------------------------------------------------------------------
      INTEGER  ::   ji, jj, jk           ! dummy loop argument
      REAL(wp) ::   zcoeft, zcoefw   ! temporary scalars
      REAL(wp) ::   ztmpu,  ztmpv,  ztmpf
      REAL(wp) ::   ztmpu1, ztmpv1, ztmpf1
      !
      REAL(wp), POINTER, DIMENSION(:,:,:) :: z_gsigw3, z_gsigt3, z_gsi3w3
      REAL(wp), POINTER, DIMENSION(:,:,:) :: z_esigt3, z_esigw3, z_esigtu3, z_esigtv3, z_esigtf3, z_esigwu3, z_esigwv3           
      !!----------------------------------------------------------------------

      CALL wrk_alloc( jpi,jpj,jpk,   z_gsigw3, z_gsigt3, z_gsi3w3                                      )
      CALL wrk_alloc( jpi,jpj,jpk,   z_esigt3, z_esigw3, z_esigtu3, z_esigtv3, z_esigtf3, z_esigwu3, z_esigwv3 )

      z_gsigw3  = 0._wp   ;   z_gsigt3  = 0._wp   ;   z_gsi3w3  = 0._wp
      z_esigt3  = 0._wp   ;   z_esigw3  = 0._wp 
      z_esigtu3 = 0._wp   ;   z_esigtv3 = 0._wp   ;   z_esigtf3 = 0._wp
      z_esigwu3 = 0._wp   ;   z_esigwv3 = 0._wp
      !
      DO ji = 1, jpi
         DO jj = 1, jpj
            !
            IF( hbatt(ji,jj) > rn_hc ) THEN    !deep water, stretched sigma
               DO jk = 1, jpk
                  z_gsigw3(ji,jj,jk) = -fssig1( REAL(jk,wp)-0.5_wp, rn_bb )
                  z_gsigt3(ji,jj,jk) = -fssig1( REAL(jk,wp)       , rn_bb )
               END DO
            ELSE ! shallow water, uniform sigma
               DO jk = 1, jpk
                  z_gsigw3(ji,jj,jk) =   REAL(jk-1,wp)            / REAL(jpk-1,wp)
                  z_gsigt3(ji,jj,jk) = ( REAL(jk-1,wp) + 0.5_wp ) / REAL(jpk-1,wp)
                  END DO
            ENDIF
            !
            DO jk = 1, jpkm1
               z_esigt3(ji,jj,jk  ) = z_gsigw3(ji,jj,jk+1) - z_gsigw3(ji,jj,jk)
               z_esigw3(ji,jj,jk+1) = z_gsigt3(ji,jj,jk+1) - z_gsigt3(ji,jj,jk)
            END DO
            z_esigw3(ji,jj,1  ) = 2._wp * ( z_gsigt3(ji,jj,1  ) - z_gsigw3(ji,jj,1  ) )
            z_esigt3(ji,jj,jpk) = 2._wp * ( z_gsigt3(ji,jj,jpk) - z_gsigw3(ji,jj,jpk) )
            !
            ! Coefficients for vertical depth as the sum of e3w scale factors
            z_gsi3w3(ji,jj,1) = 0.5_wp * z_esigw3(ji,jj,1)
            DO jk = 2, jpk
               z_gsi3w3(ji,jj,jk) = z_gsi3w3(ji,jj,jk-1) + z_esigw3(ji,jj,jk)
            END DO
            !
            DO jk = 1, jpk
               zcoeft = ( REAL(jk,wp) - 0.5_wp ) / REAL(jpkm1,wp)
               zcoefw = ( REAL(jk,wp) - 1.0_wp ) / REAL(jpkm1,wp)
               gdept_0(ji,jj,jk) = ( scosrf(ji,jj) + (hbatt(ji,jj)-rn_hc)*z_gsigt3(ji,jj,jk)+rn_hc*zcoeft )
               gdepw_0(ji,jj,jk) = ( scosrf(ji,jj) + (hbatt(ji,jj)-rn_hc)*z_gsigw3(ji,jj,jk)+rn_hc*zcoefw )
               gde3w_0(ji,jj,jk) = ( scosrf(ji,jj) + (hbatt(ji,jj)-rn_hc)*z_gsi3w3(ji,jj,jk)+rn_hc*zcoeft )
            END DO
           !
         END DO   ! for all jj's
      END DO    ! for all ji's

      DO ji = 1, jpim1
         DO jj = 1, jpjm1
            ! extended for Wetting/Drying case
            ztmpu  = hbatt(ji,jj)+hbatt(ji+1,jj)
            ztmpv  = hbatt(ji,jj)+hbatt(ji,jj+1)
            ztmpf  = hbatt(ji,jj)+hbatt(ji+1,jj)+hbatt(ji,jj+1)+hbatt(ji+1,jj+1)
            ztmpu1 = hbatt(ji,jj)*hbatt(ji+1,jj)
            ztmpv1 = hbatt(ji,jj)*hbatt(ji,jj+1)
            ztmpf1 = MIN(hbatt(ji,jj), hbatt(ji+1,jj), hbatt(ji,jj+1), hbatt(ji+1,jj+1)) * &
                   & MAX(hbatt(ji,jj), hbatt(ji+1,jj), hbatt(ji,jj+1), hbatt(ji+1,jj+1))
            DO jk = 1, jpk
                 z_esigtu3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigt3(ji,jj,jk)+hbatt(ji+1,jj)*z_esigt3(ji+1,jj,jk) ) &
                        &              / ztmpu
                 z_esigwu3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigw3(ji,jj,jk)+hbatt(ji+1,jj)*z_esigw3(ji+1,jj,jk) ) &
                        &              / ztmpu

                 z_esigtv3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigt3(ji,jj,jk)+hbatt(ji,jj+1)*z_esigt3(ji,jj+1,jk) ) &
                        &              / ztmpv
                 z_esigwv3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigw3(ji,jj,jk)+hbatt(ji,jj+1)*z_esigw3(ji,jj+1,jk) ) &
                        &              / ztmpv

                 z_esigtf3(ji,jj,jk) = ( hbatt(ji  ,jj  )*z_esigt3(ji  ,jj  ,jk)                               &
                        &            +   hbatt(ji+1,jj  )*z_esigt3(ji+1,jj  ,jk)                               &
                        &            +   hbatt(ji  ,jj+1)*z_esigt3(ji  ,jj+1,jk)                               &
                        &            +   hbatt(ji+1,jj+1)*z_esigt3(ji+1,jj+1,jk) ) / ztmpf

               !
               e3t_0(ji,jj,jk) = ( (hbatt(ji,jj)-rn_hc)*z_esigt3 (ji,jj,jk) + rn_hc/REAL(jpkm1,wp) )
               e3u_0(ji,jj,jk) = ( (hbatu(ji,jj)-rn_hc)*z_esigtu3(ji,jj,jk) + rn_hc/REAL(jpkm1,wp) )
               e3v_0(ji,jj,jk) = ( (hbatv(ji,jj)-rn_hc)*z_esigtv3(ji,jj,jk) + rn_hc/REAL(jpkm1,wp) )
               e3f_0(ji,jj,jk) = ( (hbatf(ji,jj)-rn_hc)*z_esigtf3(ji,jj,jk) + rn_hc/REAL(jpkm1,wp) )
               !
               e3w_0 (ji,jj,jk) = ( (hbatt(ji,jj)-rn_hc)*z_esigw3 (ji,jj,jk) + rn_hc/REAL(jpkm1,wp) )
               e3uw_0(ji,jj,jk) = ( (hbatu(ji,jj)-rn_hc)*z_esigwu3(ji,jj,jk) + rn_hc/REAL(jpkm1,wp) )
               e3vw_0(ji,jj,jk) = ( (hbatv(ji,jj)-rn_hc)*z_esigwv3(ji,jj,jk) + rn_hc/REAL(jpkm1,wp) )
            END DO
        END DO
      END DO
      !
      CALL wrk_dealloc( jpi,jpj,jpk,   z_gsigw3, z_gsigt3, z_gsi3w3                                      )
      CALL wrk_dealloc( jpi,jpj,jpk,   z_esigt3, z_esigw3, z_esigtu3, z_esigtv3, z_esigtf3, z_esigwu3, z_esigwv3 )
      !
   END SUBROUTINE s_sh94


   SUBROUTINE s_sf12
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE s_sf12 *** 
      !!                     
      !! ** Purpose :   stretch the s-coordinate system
      !!
      !! ** Method  :   s-coordinate stretch using the Siddorn and Furner 2012?
      !!                mixed S/sigma/Z coordinate
      !!
      !!                This method allows the maintenance of fixed surface and or
      !!                bottom cell resolutions (cf. geopotential coordinates) 
      !!                within an analytically derived stretched S-coordinate framework.
      !!
      !!
      !! Reference : Siddorn and Furner 2012 (submitted Ocean modelling).
      !!----------------------------------------------------------------------
      INTEGER  ::   ji, jj, jk           ! dummy loop argument
      REAL(wp) ::   zsmth               ! smoothing around critical depth
      REAL(wp) ::   zzs, zzb           ! Surface and bottom cell thickness in sigma space
      REAL(wp) ::   ztmpu, ztmpv, ztmpf
      REAL(wp) ::   ztmpu1, ztmpv1, ztmpf1
      !
      REAL(wp), POINTER, DIMENSION(:,:,:) :: z_gsigw3, z_gsigt3, z_gsi3w3
      REAL(wp), POINTER, DIMENSION(:,:,:) :: z_esigt3, z_esigw3, z_esigtu3, z_esigtv3, z_esigtf3, z_esigwu3, z_esigwv3           
      !!----------------------------------------------------------------------
      !
      CALL wrk_alloc( jpi, jpj, jpk, z_gsigw3, z_gsigt3, z_gsi3w3                                      )
      CALL wrk_alloc( jpi, jpj, jpk, z_esigt3, z_esigw3, z_esigtu3, z_esigtv3, z_esigtf3, z_esigwu3, z_esigwv3 )

      z_gsigw3  = 0._wp   ;   z_gsigt3  = 0._wp   ;   z_gsi3w3  = 0._wp
      z_esigt3  = 0._wp   ;   z_esigw3  = 0._wp 
      z_esigtu3 = 0._wp   ;   z_esigtv3 = 0._wp   ;   z_esigtf3 = 0._wp
      z_esigwu3 = 0._wp   ;   z_esigwv3 = 0._wp

      DO ji = 1, jpi
         DO jj = 1, jpj

          IF (hbatt(ji,jj)>rn_hc) THEN !deep water, stretched sigma
              
              zzb = hbatt(ji,jj)*rn_zb_a + rn_zb_b   ! this forces a linear bottom cell depth relationship with H,.
                                                     ! could be changed by users but care must be taken to do so carefully
              zzb = 1.0_wp-(zzb/hbatt(ji,jj))
            
              zzs = rn_zs / hbatt(ji,jj) 
              
              IF (rn_efold /= 0.0_wp) THEN
                zsmth   = tanh( (hbatt(ji,jj)- rn_hc ) / rn_efold )
              ELSE
                zsmth = 1.0_wp 
              ENDIF
               
              DO jk = 1, jpk
                z_gsigw3(ji,jj,jk) =  REAL(jk-1,wp)        /REAL(jpk-1,wp)
                z_gsigt3(ji,jj,jk) = (REAL(jk-1,wp)+0.5_wp)/REAL(jpk-1,wp)
              ENDDO
              z_gsigw3(ji,jj,:) = fgamma( z_gsigw3(ji,jj,:), zzb, zzs, zsmth  )
              z_gsigt3(ji,jj,:) = fgamma( z_gsigt3(ji,jj,:), zzb, zzs, zsmth  )
 
          ELSE IF (ln_sigcrit) THEN ! shallow water, uniform sigma

            DO jk = 1, jpk
              z_gsigw3(ji,jj,jk) =  REAL(jk-1,wp)     /REAL(jpk-1,wp)
              z_gsigt3(ji,jj,jk) = (REAL(jk-1,wp)+0.5)/REAL(jpk-1,wp)
            END DO

          ELSE  ! shallow water, z coordinates

            DO jk = 1, jpk
              z_gsigw3(ji,jj,jk) =  REAL(jk-1,wp)        /REAL(jpk-1,wp)*(rn_hc/hbatt(ji,jj))
              z_gsigt3(ji,jj,jk) = (REAL(jk-1,wp)+0.5_wp)/REAL(jpk-1,wp)*(rn_hc/hbatt(ji,jj))
            END DO

          ENDIF

          DO jk = 1, jpkm1
             z_esigt3(ji,jj,jk) = z_gsigw3(ji,jj,jk+1) - z_gsigw3(ji,jj,jk)
             z_esigw3(ji,jj,jk+1) = z_gsigt3(ji,jj,jk+1) - z_gsigt3(ji,jj,jk)
          END DO
          z_esigw3(ji,jj,1  ) = 2.0_wp * (z_gsigt3(ji,jj,1  ) - z_gsigw3(ji,jj,1  ))
          z_esigt3(ji,jj,jpk) = 2.0_wp * (z_gsigt3(ji,jj,jpk) - z_gsigw3(ji,jj,jpk))

          ! Coefficients for vertical depth as the sum of e3w scale factors
          z_gsi3w3(ji,jj,1) = 0.5 * z_esigw3(ji,jj,1)
          DO jk = 2, jpk
             z_gsi3w3(ji,jj,jk) = z_gsi3w3(ji,jj,jk-1) + z_esigw3(ji,jj,jk)
          END DO

          DO jk = 1, jpk
             gdept_0(ji,jj,jk) = (scosrf(ji,jj)+hbatt(ji,jj))*z_gsigt3(ji,jj,jk)
             gdepw_0(ji,jj,jk) = (scosrf(ji,jj)+hbatt(ji,jj))*z_gsigw3(ji,jj,jk)
             gde3w_0(ji,jj,jk) = (scosrf(ji,jj)+hbatt(ji,jj))*z_gsi3w3(ji,jj,jk)
          END DO

        ENDDO   ! for all jj's
      ENDDO    ! for all ji's

      DO ji=1,jpi-1
        DO jj=1,jpj-1

           ! extend to suit for Wetting/Drying case
           ztmpu  = hbatt(ji,jj)+hbatt(ji+1,jj)
           ztmpv  = hbatt(ji,jj)+hbatt(ji,jj+1)
           ztmpf  = hbatt(ji,jj)+hbatt(ji+1,jj)+hbatt(ji,jj+1)+hbatt(ji+1,jj+1)
           ztmpu1 = hbatt(ji,jj)*hbatt(ji+1,jj)
           ztmpv1 = hbatt(ji,jj)*hbatt(ji,jj+1)
           ztmpf1 = MIN(hbatt(ji,jj), hbatt(ji+1,jj), hbatt(ji,jj+1), hbatt(ji+1,jj+1)) * &
                  & MAX(hbatt(ji,jj), hbatt(ji+1,jj), hbatt(ji,jj+1), hbatt(ji+1,jj+1))
           DO jk = 1, jpk
                z_esigtu3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigt3(ji,jj,jk)+hbatt(ji+1,jj)*z_esigt3(ji+1,jj,jk) ) &
                       &              / ztmpu
                z_esigwu3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigw3(ji,jj,jk)+hbatt(ji+1,jj)*z_esigw3(ji+1,jj,jk) ) &
                       &              / ztmpu
                z_esigtv3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigt3(ji,jj,jk)+hbatt(ji,jj+1)*z_esigt3(ji,jj+1,jk) ) &
                       &              / ztmpv
                z_esigwv3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigw3(ji,jj,jk)+hbatt(ji,jj+1)*z_esigw3(ji,jj+1,jk) ) &
                       &              / ztmpv

                z_esigtf3(ji,jj,jk) = ( hbatt(ji  ,jj  )*z_esigt3(ji  ,jj  ,jk)                               &
                       &              + hbatt(ji+1,jj  )*z_esigt3(ji+1,jj  ,jk)                               &
                       &              + hbatt(ji  ,jj+1)*z_esigt3(ji  ,jj+1,jk)                               &
                       &              + hbatt(ji+1,jj+1)*z_esigt3(ji+1,jj+1,jk) ) / ztmpf

             ! Code prior to wetting and drying option (for reference)
             !z_esigtu3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigt3(ji,jj,jk)+hbatt(ji+1,jj)*z_esigt3(ji+1,jj,jk) )   &
             !                     /( hbatt(ji,jj)+hbatt(ji+1,jj) )
             !
             !z_esigwu3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigw3(ji,jj,jk)+hbatt(ji+1,jj)*z_esigw3(ji+1,jj,jk) )   &
             !                     /( hbatt(ji,jj)+hbatt(ji+1,jj) )
             !
             !z_esigtv3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigt3(ji,jj,jk)+hbatt(ji,jj+1)*z_esigt3(ji,jj+1,jk) )   &
             !                     /( hbatt(ji,jj)+hbatt(ji,jj+1) )
             !
             !z_esigwv3(ji,jj,jk) = ( hbatt(ji,jj)*z_esigw3(ji,jj,jk)+hbatt(ji,jj+1)*z_esigw3(ji,jj+1,jk) )   &
             !                     /( hbatt(ji,jj)+hbatt(ji,jj+1) )
             !
             !z_esigtf3(ji,jj,jk) = ( hbatt(ji  ,jj  )*z_esigt3(ji  ,jj  ,jk)                                 &
             !                    &  +hbatt(ji+1,jj  )*z_esigt3(ji+1,jj  ,jk)                                 &
             !                       +hbatt(ji  ,jj+1)*z_esigt3(ji  ,jj+1,jk)                                 &
             !                    &  +hbatt(ji+1,jj+1)*z_esigt3(ji+1,jj+1,jk) )                               &
             !                     /( hbatt(ji  ,jj  )+hbatt(ji+1,jj)+hbatt(ji,jj+1)+hbatt(ji+1,jj+1) )

             e3t_0(ji,jj,jk)=(scosrf(ji,jj)+hbatt(ji,jj))*z_esigt3(ji,jj,jk)
             e3u_0(ji,jj,jk)=(scosrf(ji,jj)+hbatu(ji,jj))*z_esigtu3(ji,jj,jk)
             e3v_0(ji,jj,jk)=(scosrf(ji,jj)+hbatv(ji,jj))*z_esigtv3(ji,jj,jk)
             e3f_0(ji,jj,jk)=(scosrf(ji,jj)+hbatf(ji,jj))*z_esigtf3(ji,jj,jk)
             !
             e3w_0 (ji,jj,jk)=hbatt(ji,jj)*z_esigw3(ji,jj,jk)
             e3uw_0(ji,jj,jk)=hbatu(ji,jj)*z_esigwu3(ji,jj,jk)
             e3vw_0(ji,jj,jk)=hbatv(ji,jj)*z_esigwv3(ji,jj,jk)
          END DO

        ENDDO
      ENDDO
      !
      CALL lbc_lnk(e3t_0 ,'T',1.) ; CALL lbc_lnk(e3u_0 ,'T',1.)
      CALL lbc_lnk(e3v_0 ,'T',1.) ; CALL lbc_lnk(e3f_0 ,'T',1.)
      CALL lbc_lnk(e3w_0 ,'T',1.)
      CALL lbc_lnk(e3uw_0,'T',1.) ; CALL lbc_lnk(e3vw_0,'T',1.)
      !
      CALL wrk_dealloc( jpi,jpj,jpk,   z_gsigw3, z_gsigt3, z_gsi3w3                                      )
      CALL wrk_dealloc( jpi,jpj,jpk,   z_esigt3, z_esigw3, z_esigtu3, z_esigtv3, z_esigtf3, z_esigwu3, z_esigwv3 )
      !
   END SUBROUTINE s_sf12


   SUBROUTINE s_tanh()
      !!----------------------------------------------------------------------
      !!                  ***  ROUTINE s_tanh*** 
      !!                     
      !! ** Purpose :   stretch the s-coordinate system
      !!
      !! ** Method  :   s-coordinate stretch 
      !!
      !! Reference : Madec, Lott, Delecluse and Crepon, 1996. JPO, 26, 1393-1408.
      !!----------------------------------------------------------------------
      INTEGER  ::   ji, jj, jk       ! dummy loop argument
      REAL(wp) ::   zcoeft, zcoefw   ! temporary scalars
      REAL(wp), POINTER, DIMENSION(:) :: z_gsigw, z_gsigt, z_gsi3w
      REAL(wp), POINTER, DIMENSION(:) :: z_esigt, z_esigw
      !!----------------------------------------------------------------------

      CALL wrk_alloc( jpk,   z_gsigw, z_gsigt, z_gsi3w )
      CALL wrk_alloc( jpk,   z_esigt, z_esigw )

      z_gsigw  = 0._wp   ;   z_gsigt  = 0._wp   ;   z_gsi3w  = 0._wp
      z_esigt  = 0._wp   ;   z_esigw  = 0._wp 

      DO jk = 1, jpk
        z_gsigw(jk) = -fssig( REAL(jk,wp)-0.5_wp )
        z_gsigt(jk) = -fssig( REAL(jk,wp)        )
      END DO
      IF( nprint == 1 .AND. lwp )   WRITE(numout,*) 'z_gsigw 1 jpk    ', z_gsigw(1), z_gsigw(jpk)
      !
      ! Coefficients for vertical scale factors at w-, t- levels
!!gm bug :  define it from analytical function, not like juste bellow....
!!gm        or betteroffer the 2 possibilities....
      DO jk = 1, jpkm1
         z_esigt(jk  ) = z_gsigw(jk+1) - z_gsigw(jk)
         z_esigw(jk+1) = z_gsigt(jk+1) - z_gsigt(jk)
      END DO
      z_esigw( 1 ) = 2._wp * ( z_gsigt(1  ) - z_gsigw(1  ) ) 
      z_esigt(jpk) = 2._wp * ( z_gsigt(jpk) - z_gsigw(jpk) )
      !
      ! Coefficients for vertical depth as the sum of e3w scale factors
      z_gsi3w(1) = 0.5_wp * z_esigw(1)
      DO jk = 2, jpk
         z_gsi3w(jk) = z_gsi3w(jk-1) + z_esigw(jk)
      END DO
!!gm: depuw, depvw can be suppressed (modif in ldfslp) and depw=dep3w can be set (save 3 3D arrays)
      DO jk = 1, jpk
         zcoeft = ( REAL(jk,wp) - 0.5_wp ) / REAL(jpkm1,wp)
         zcoefw = ( REAL(jk,wp) - 1.0_wp ) / REAL(jpkm1,wp)
         gdept_0(:,:,jk) = ( scosrf(:,:) + (hbatt(:,:)-hift(:,:))*z_gsigt(jk) + hift(:,:)*zcoeft )
         gdepw_0(:,:,jk) = ( scosrf(:,:) + (hbatt(:,:)-hift(:,:))*z_gsigw(jk) + hift(:,:)*zcoefw )
         gde3w_0(:,:,jk) = ( scosrf(:,:) + (hbatt(:,:)-hift(:,:))*z_gsi3w(jk) + hift(:,:)*zcoeft )
      END DO
!!gm: e3uw, e3vw can be suppressed  (modif in dynzdf, dynzdf_iso, zdfbfr) (save 2 3D arrays)
      DO jj = 1, jpj
         DO ji = 1, jpi
            DO jk = 1, jpk
              e3t_0(ji,jj,jk) = ( (hbatt(ji,jj)-hift(ji,jj))*z_esigt(jk) + hift(ji,jj)/REAL(jpkm1,wp) )
              e3u_0(ji,jj,jk) = ( (hbatu(ji,jj)-hifu(ji,jj))*z_esigt(jk) + hifu(ji,jj)/REAL(jpkm1,wp) )
              e3v_0(ji,jj,jk) = ( (hbatv(ji,jj)-hifv(ji,jj))*z_esigt(jk) + hifv(ji,jj)/REAL(jpkm1,wp) )
              e3f_0(ji,jj,jk) = ( (hbatf(ji,jj)-hiff(ji,jj))*z_esigt(jk) + hiff(ji,jj)/REAL(jpkm1,wp) )
              !
              e3w_0 (ji,jj,jk) = ( (hbatt(ji,jj)-hift(ji,jj))*z_esigw(jk) + hift(ji,jj)/REAL(jpkm1,wp) )
              e3uw_0(ji,jj,jk) = ( (hbatu(ji,jj)-hifu(ji,jj))*z_esigw(jk) + hifu(ji,jj)/REAL(jpkm1,wp) )
              e3vw_0(ji,jj,jk) = ( (hbatv(ji,jj)-hifv(ji,jj))*z_esigw(jk) + hifv(ji,jj)/REAL(jpkm1,wp) )
            END DO
         END DO
      END DO
      !
      CALL wrk_dealloc( jpk,   z_gsigw, z_gsigt, z_gsi3w )
      CALL wrk_dealloc( jpk,   z_esigt, z_esigw          )
      !
   END SUBROUTINE s_tanh


   FUNCTION fssig( pk ) RESULT( pf )
      !!----------------------------------------------------------------------
      !!                 ***  ROUTINE fssig ***
      !!       
      !! ** Purpose :   provide the analytical function in s-coordinate
      !!          
      !! ** Method  :   the function provide the non-dimensional position of
      !!                T and W (i.e. between 0 and 1)
      !!                T-points at integer values (between 1 and jpk)
      !!                W-points at integer values - 1/2 (between 0.5 and jpk-0.5)
      !!----------------------------------------------------------------------
      REAL(wp), INTENT(in) ::   pk   ! continuous "k" coordinate
      REAL(wp)             ::   pf   ! sigma value
      !!----------------------------------------------------------------------
      !
      pf =   (   TANH( rn_theta * ( -(pk-0.5_wp) / REAL(jpkm1) + rn_thetb )  )   &
         &     - TANH( rn_thetb * rn_theta                                )  )   &
         & * (   COSH( rn_theta                           )                      &
         &     + COSH( rn_theta * ( 2._wp * rn_thetb - 1._wp ) )  )              &
         & / ( 2._wp * SINH( rn_theta ) )
      !
   END FUNCTION fssig


   FUNCTION fssig1( pk1, pbb ) RESULT( pf1 )
      !!----------------------------------------------------------------------
      !!                 ***  ROUTINE fssig1 ***
      !!
      !! ** Purpose :   provide the Song and Haidvogel version of the analytical function in s-coordinate
      !!
      !! ** Method  :   the function provides the non-dimensional position of
      !!                T and W (i.e. between 0 and 1)
      !!                T-points at integer values (between 1 and jpk)
      !!                W-points at integer values - 1/2 (between 0.5 and jpk-0.5)
      !!----------------------------------------------------------------------
      REAL(wp), INTENT(in) ::   pk1   ! continuous "k" coordinate
      REAL(wp), INTENT(in) ::   pbb   ! Stretching coefficient
      REAL(wp)             ::   pf1   ! sigma value
      !!----------------------------------------------------------------------
      !
      IF ( rn_theta == 0 ) then      ! uniform sigma
         pf1 = - ( pk1 - 0.5_wp ) / REAL( jpkm1 )
      ELSE                        ! stretched sigma
         pf1 =   ( 1._wp - pbb ) * ( SINH( rn_theta*(-(pk1-0.5_wp)/REAL(jpkm1)) ) ) / SINH( rn_theta )              &
            &  + pbb * (  (TANH( rn_theta*( (-(pk1-0.5_wp)/REAL(jpkm1)) + 0.5_wp) ) - TANH( 0.5_wp * rn_theta )  )  &
            &        / ( 2._wp * TANH( 0.5_wp * rn_theta ) )  )
      ENDIF
      !
   END FUNCTION fssig1


   FUNCTION fgamma( pk1, pzb, pzs, psmth) RESULT( p_gamma )
      !!----------------------------------------------------------------------
      !!                 ***  ROUTINE fgamma  ***
      !!
      !! ** Purpose :   provide analytical function for the s-coordinate
      !!
      !! ** Method  :   the function provides the non-dimensional position of
      !!                T and W (i.e. between 0 and 1)
      !!                T-points at integer values (between 1 and jpk)
      !!                W-points at integer values - 1/2 (between 0.5 and jpk-0.5)
      !!
      !!                This method allows the maintenance of fixed surface and or
      !!                bottom cell resolutions (cf. geopotential coordinates) 
      !!                within an analytically derived stretched S-coordinate framework.
      !!
      !! Reference  :   Siddorn and Furner, in prep
      !!----------------------------------------------------------------------
      REAL(wp), INTENT(in   ) ::   pk1(jpk)       ! continuous "k" coordinate
      REAL(wp)                ::   p_gamma(jpk)   ! stretched coordinate
      REAL(wp), INTENT(in   ) ::   pzb            ! Bottom box depth
      REAL(wp), INTENT(in   ) ::   pzs            ! surface box depth
      REAL(wp), INTENT(in   ) ::   psmth          ! Smoothing parameter
      !
      INTEGER  ::   jk             ! dummy loop index
      REAL(wp) ::   za1,za2,za3    ! local scalar
      REAL(wp) ::   zn1,zn2        !   -      - 
      REAL(wp) ::   za,zb,zx       !   -      - 
      !!----------------------------------------------------------------------
      !
      zn1  =  1._wp / REAL( jpkm1, wp )
      zn2  =  1._wp -  zn1
      !
      za1 = (rn_alpha+2.0_wp)*zn1**(rn_alpha+1.0_wp)-(rn_alpha+1.0_wp)*zn1**(rn_alpha+2.0_wp) 
      za2 = (rn_alpha+2.0_wp)*zn2**(rn_alpha+1.0_wp)-(rn_alpha+1.0_wp)*zn2**(rn_alpha+2.0_wp)
      za3 = (zn2**3.0_wp - za2)/( zn1**3.0_wp - za1)
      !
      za = pzb - za3*(pzs-za1)-za2
      za = za/( zn2-0.5_wp*(za2+zn2**2.0_wp) - za3*(zn1-0.5_wp*(za1+zn1**2.0_wp) ) )
      zb = (pzs - za1 - za*( zn1-0.5_wp*(za1+zn1**2.0_wp ) ) ) / (zn1**3.0_wp - za1)
      zx = 1.0_wp-za/2.0_wp-zb
      !
      DO jk = 1, jpk
         p_gamma(jk) = za*(pk1(jk)*(1.0_wp-pk1(jk)/2.0_wp))+zb*pk1(jk)**3.0_wp +  &
            &          zx*( (rn_alpha+2.0_wp)*pk1(jk)**(rn_alpha+1.0_wp)- &
            &               (rn_alpha+1.0_wp)*pk1(jk)**(rn_alpha+2.0_wp) )
        p_gamma(jk) = p_gamma(jk)*psmth+pk1(jk)*(1.0_wp-psmth)
      END DO
      !
   END FUNCTION fgamma

   !!======================================================================
END MODULE domzgr
