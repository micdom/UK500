# NEMO-RELOC
Relocatable NEMO configurations

These guides will help you save time, so that you can do other stuff.

This file is in the root project directory and is loaded in the index.html page. It would be good to put the project description here.

Recipe Releases
===============

A number of branches (currently one) are 'released' when a recipe is sharable

**LBay_NEMO4_livljobs4_archer_v0**: A Liverpool Bay configuration using NEMOv4 from GEBCO bathymetry.
Forced with TPXO and NNA tidal boundary forcing.
Set up includes description of T,S initial conditions;  T and S boundary forcing, and met forcing, though these are not switched on in the demonstration.
This configuration is run on ARCHER and built on livljobs4/ARCHER.
Principle recipe: ``LBay_archer_livljobs4``


Summary of contents
===================

* build_XIOS2: Since we do not need to keep reproducing instructions for building XIOS it is abstracted here. This is a build of XIOS2, which is required for NEMO v4. XIOS1 is used for v3.6

* build_opa_orchestra: Similarly the compilation of OPA does not need to be repeated in each recipe. Here it is abstracted for NEMO v4. (Though at the time of writing I didn't have a complete demo of v4..). This code base is developed under the ORCHESTRA project.

* LBay: This was a port of the Lighthouse Reef config setup to a new location, using ARCHER. However some java stuff broke on ARCHER so tools, PyNEMO in particular, were moved to livljobs.

* LBay_archer_livljobs4 (formerly ``LBay_livljobs4``): Because of the java problems, this recipe uses livljobs4 to build input files but runs the code on ARCHER. This
was developed for v3.6 then updated to v4. Noticed a problem with e[12]* varibles being generated wrong in GRIDGEN. Use NEST instead. During v4 development it was helpful to also ingest namelist_cfg files into the repository to track what did and didn't work. These files included: LBay_v3_namelist_cfg (where I started with a working namelist in v3.6); EA_namelist_cfg (working simulation in v4, but not DOMAINcfg, from jdha); LBay_v4_namelist_cfg (destination namelist_cfg in v4).

* LBay_mobius: Since MDP can not run on ARCHER. This is a port of ``LBay_livljobs4`` onto NOCL's MOBIUS cluster. This is incomplete *(16 Oct 17)*.

* SEAsia_mobius: Started building a SE Asia domain for the ACCORD project. Started with v3.6 with the aim of updating. Started with the intention of doing everying on liverpool machines so that Tom could emulate it for SW Pacific. However I was needing to make progress and didn't have all the tools ready at liverpool so switch to using a mix of ARCHER and livljobs4 in ``SEAsia``

* SEAsia: Having started soley on liverpool machines for this domain, I carried on with a mix also using ARCHER. Stopped when I discovered the server with ORCA12 data was terminated.

At this stage in the development it became apparent that we might want to switch to using NEMO v4 (and suck it up sooner than later). The ORCHESTRA project had a working code base so it made sense to start with that trunk release. v4 has a lot of fixes but also has a restructured namelist and an abstracted domain mesh and mask configuration step.

* EAfrica: This configuration was generated by jdha for the ACCORD proposal, using v4. This recipe ports and runs that domain to the local user. The code is compiled but forcings are taken from jdha. The new domain_cfg.nc is generated in the recipe.
This is a tide only simulation.

* LBay_180m: In v4 a significant challenge is in getting the new namelists to work. Having made progress in LBay_livljobs4 on branch ``LBay-orchestra-code-base`` but run into GRIDGEN problems. Decided to make a new branch and start with the old 180m POLCOMS bathymetry and coordinates file for Liverpool Bay. This gets a new branch (incase we fix the GRIDGEN problem). At the time of writing this is where I am. *(16 Oct)*

---

* quickplotNEMO.py: python script to look at NEMO output and see if it is sensible. Reads grid_T.nc, Tides.nc or domain_cfg.nc output

---

* Solent: This is actually an empty config template. I plan to do this domain with AMM60 boundaries.
