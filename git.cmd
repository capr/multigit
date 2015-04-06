@echo off
setlocal enabledelayedexpansion
rem find sh.exe from a git installation and run our git wrapper with it.
rem for this to work git.exe must be in PATH and sh.exe must be in ../bin.
:begin
	set ZERO=%0
	pushd "%~dp0"
	if [%cd%\] == [%~dp0] goto callmain
	if [%cd%]  == [%~dp0] goto callmain
	echo ERROR: Could not change dir to "%~dp0"
	goto aftermain
	goto end
:callmain
	call :main %*
:aftermain
	popd
	endlocal
	goto end
:main
	call :set_dir git.exe
	if exist !dir! goto git_found
	goto git_not_found
:set_dir
	set dir=%~$PATH:1
	goto end
:git_found
	set PATH=/usr/local/bin:/mingw/bin:/bin
	"%dir:~0,-12%"\bin\sh.exe --norc ./git %*
	goto end
:git_not_found
	echo git.exe not found in PATH
	goto end
:end
