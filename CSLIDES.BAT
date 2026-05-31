@echo off
rem ************ CSlides.bat ********
rem  Perforns a Cshow slide show using Stuffkey and Cshow.key

rem  Load stuffkey using file cshow.key. Change dir if needed!
stuffkey /Scs /F:cshow.key
if not errorlevel == 0 goto error

rem  Change to or supply Cshow.exe and picture directories!
cshow %1 %2 %3 %4 %5 %6 %7

rem  Now unload stuffkey
stuffkey /Scs /R
goto end

:error
echo Error running stuffkey...aborting.
goto end

:end

