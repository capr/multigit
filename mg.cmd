@echo off
rem find sh.exe from a git installation and run our git wrapper with it.
rem for this to work git.exe must be in PATH and sh.exe must be in ../bin.
:begin
	setlocal enabledelayedexpansion
	set "ZERO=%0"
	call :set_dir git.exe
	if exist !dir! goto git_found
	goto git_not_found
:set_dir
	set "dir=%~$PATH:1"
	goto end
:git_found
	set PATH=/bin
	"%dir:~0,-12%\bin\sh.exe" "%~dp0mg" %*
	goto end
:git_not_found
	echo git.exe not found in PATH
	goto end
:end
	endlocal
