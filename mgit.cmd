@echo off
setlocal enabledelayedexpansion
REM # Find bash.exe from a git installation and run our git wrapper with it.
REM # For this to work git.exe must be in PATH and bash.exe must be
REM # in ../bin (MSysGit) or ../usr/bin (Git for Windows).
:begin
	call :set_dir git.exe
	if exist !dir! goto git_found
	goto git_not_found
:set_dir
	set "dir=%~$PATH:1"
	goto end
:git_found
	rem set PATH so that local binaries take priority over MSYS ones.
	set "PATH=/bin;%PATH%"
	set "BASH=%dir:~0,-12%\bin\bash.exe"
	if not exist "%BASH%" set "BASH=%dir:~0,-12%\usr\bin\bash.exe"
	"%BASH%" "%~dp0mgit" %*
	goto end
:git_not_found
	echo git.exe not found in PATH
	goto end
:end
