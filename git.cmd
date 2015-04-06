@echo off
goto begin

:usage
	if [%1] == [] goto usage1
	echo.
	echo ERROR: %*
	echo.
	goto end
:usage1
	echo.
	echo  Multigit 0.1 - git wrapper for working with overlaid repos.
	echo  Written by Cosmin Apreutesei. Public Domain.
	echo.
	echo  USAGE:
	echo.
	echo    %Z% ls-all                          list all known packages
	echo    %Z% ls-uncloned                     list not yet cloned packages
	echo    %Z% ls-cloned                       list cloned packages
	echo    %Z% ls-modified                     list packages that were modified locally
	echo    %Z% ls-unpushed                     list packages that are ahead of origin
	echo    %Z% ls-untracked                    list files untracked by any repo (needs MSYS)
	echo    %Z% ls-double-tracked               list files tracked by multiple repos (needs MSYS)
	echo    %Z% clone ^<package^> ^[origin ^| url^]  clone a package
	echo    %Z% clone-all [fetch-options]       clone all uncloned packages
	echo    %Z% unclone ^<package^>               remove a cloned package from disk (!)
	echo    %Z% ^<package^>^|--all up ^[message^]    add/commit/push combo
	echo    %Z% ^<package^>^|--all uptag           update current tag to point to current commit
	echo    %Z% ^<package^>^|--all ver             show package version
	echo    %Z% ^<package^>^|--all clear-history   clear the entire history of the current branch (!)
	echo    %Z% ^<package^>^|--all update-perms    chmod+x all .sh files in package (in git)
	echo    %Z% ^<package^>^|--all command ...     execute any git command on a package repo
	echo    %Z% ^<package^>                       start a git subshell for a package repo
	echo    %Z% platform                        show current platform
	echo    %Z% ^[help^|--help^]                   this screen
	echo.
	goto end

:list_known
	for %%f in (.multigit/*.origin) do call :list_known1 %%f
	goto end
:list_known1
	set s=%1
	set s=%s:.origin=%
	echo %s%
	goto end

:list_cloned
	for %%f in (.multigit/*.origin) do call :list_cloned1 %%f
	goto end
:list_cloned1
	set s=%1
	set s=%s:.origin=%
	if exist .multigit/%s%/.git echo %s%
	goto end

:list_uncloned
	for %%f in (.multigit/*.origin) do call :list_uncloned1 %%f
	goto end
:list_uncloned1
	set s=%1
	set s=%s:.origin=%
	if not exist .multigit/%s%/.git echo %s%
	goto end

:foreach_cloned
	set MULTIGIT_PACKAGE1=MULTIGIT_PACKAGE
	set GIT_DIR1=GIT_DIR
	set GIT_DIR=
	set MULTIGIT_PACKAGE=
	for /f "tokens=* delims= " %%p in ('%Z% ls-cloned') do call %Z% %%p %*
	set MULTIGIT_PACKAGE=MULTIGIT_PACKAGE1
	set GIT_DIR=GIT_DIR1
	goto end

:list_modified
	call :foreach_cloned status -s
	goto end

:list_unpushed
	for /f "tokens=* delims= " %%p in ('%Z% ls-cloned') do call :list_unpushed1 %%p
	goto end
:list_unpushed1
	set GIT_DIR=.multigit/%1/.git
	set "cmd=git.exe rev-list HEAD...origin/master --count"
	for /f "delims=" %%i in ('%cmd%') do if not "%%i" == "0" echo %1
	goto end

:list_untracked
	sh ./git ls-untracked
	goto end

:list_double_tracked
	sh ./git ls-double-tracked
	goto end

:clone_all
	set GIT_FETCH_OPTS=%*
	for /f "tokens=* delims= " %%p in ('%Z% ls-uncloned') do call %Z% clone %%p
	goto end

:clone
	if [%1] == [] call :usage Package name expected. & goto end
	if exist .multigit/%1/.git/nul call :usage Pacakge "%1" is already cloned. & goto end

	if [%2] == [] (
		if not exist .multigit/%1.origin call :usage File not found ".multigit/%1.origin". & goto end
		for /f "delims=" %%o in (.multigit/%1.origin) do (
			if exist .multigit/%%o.baseurl (
				for /f "delims=" %%u in (.multigit/%%o.baseurl) do set url=%%u%1
			) else (
				set url=%%o
			)
		)
	) else (
		set origin=%2
		if exist .multigit/%origin%.baseurl (
			for /f "delims=" %%s in (.multigit/%origin%.baseurl) do set url=%%s%1
		) else (
			set url=%origin%
		)
	)

	rem set the .gitignore file for multigit on the first clone operation.
	git.exe config core.excludesfile .multigit/.exclude

	md .multigit\%1
	set GIT_DIR=.multigit/%1/.git

	git.exe init
	git.exe config --local core.worktree ../../..
	git.exe config --local core.excludesfile .multigit/%1.exclude
	git.exe remote add origin %url%
	git.exe fetch %GIT_FETCH_OPTS%
	if %errorlevel% neq 0 (
		rmdir .multigit/%1/.git /s /q
		call :usage git fetch error. & goto end
	)
	git.exe branch --track master origin/master
	git.exe checkout

	rem register the package if new
	if not [%origin%] == [] echo %origin% > .multigit/%1.origin
	goto end

:unclone
	if [%1] == [] call :usage Missing package. & goto end
	if not [%GIT_DIR%] == [] call :usage Cannot unclone from a subshell. & goto end
	if not exist .multigit/%1/.git/nul call :usage Package not found "%1". & goto end
	for /f "delims=" %%i in ('%Z% %1 ls-tree -r --name-only HEAD') do call :remove_file %%i
	for /f "delims=" %%i in ('%Z% %1 ls-tree -r --name-only HEAD') do call :remove_empty_dir %%i
	rd /S /Q .multigit\%1
	goto end
:remove_file
	set file=%1
	set file=%file:/=\%
	del %file%
	goto end
:remove_empty_dir
	set file="%~dp1"
	set file=%file:/=\%
	rd %file% 2>nul
	goto end

:platform
	if [%PROCESSOR_ARCHITECTURE%] == [AMD64] echo mingw64 & goto end
	if [%PROCESSOR_ARCHITEW6432%] == [AMD64] echo mingw64 & goto end
	echo mingw32
	goto end

:git_shell
	echo Entering subshell: git commands will work on package "%MULTIGIT_PACKAGE%".
	echo Type `exit' to exit subshell.
	call git.exe status -s
	set "PROMPT=[%MULTIGIT_PACKAGE%] $P$G"
	cmd /k
	goto end

:git_up
	set msg=%1
	if [%1] == [] set msg=unimportant

	git.exe add -A
	git.exe commit -m %msg%
	git.exe push
	goto end

:git_uptag
	set "cmd=git.exe describe --tags --abbrev^=0"
	for /f "delims=" %%i in ('%cmd%') do call :git_uptag1 %%i
	goto end
:git_uptag1
	if [%1] == [] call :usage No current tag to update. Make a tag first. & goto end
	git.exe tag -f %1
	git.exe push -f --tags
	goto end

:git_ver
	set "s=%MULTIGIT_PACKAGE                              "
	set "s=%s:~0,20%"
	for /f "delims=" %%i in ('git.exe describe --tags --long --always') do echo %s%%%i
	goto end

:git_clear_history
	set "cmd=git.exe rev-parse --abbrev-ref HEAD"
	for /f "delims=" %%i in ('%cmd%') do call :git_clear_history1 %%i
	goto end
:git_clear_history1
	git.exe checkout --orphan delete_me
	git.exe add -A
	git.exe commit -m "init (history cleared)"
	git.exe branch -D %1
	git.exe branch -m %1
	goto end

:git_update_perms
	for /f "delims=" %%i in ('%Z% %MULTIGIT_PACKAGE% ls-files') do call :git_update_perms1 %%i %%~xi
	goto end
:git_update_perms1
	if [%2] == [.sh] git.exe update-index --chmod=+x %1
	goto end

:git_cmd
	if [%1] == [--all] goto git_cmd_all
	if [%1] == [-a] goto git_cmd_all
	goto git_cmd_cont
:git_cmd_all
	shift
	if [%1] == [] call :usage Refusing to start a subshell for each package. & goto end
	call :foreach_cloned %1 %2 %3 %4 %5 %6 %7 %8 %9
	goto end
:git_cmd_cont
	set pkg=%MULTIGIT_PACKAGE%
	if [%pkg%] == [] goto git_cmd1
	goto git_cmd2
:git_cmd1
	set pkg=%1
	shift
:git_cmd2
	set GIT_DIR=.multigit/%pkg%/.git
	set MULTIGIT_PACKAGE=%pkg%
	if not exist %GIT_DIR%/nul call :usage Unknown package "%pkg%". & goto end

	if [%1] == [] call :git_shell & goto end
	if [%1] == [up] call :git_up %2 & goto end
	if [%1] == [uptag] call :git_uptag & goto end
	if [%1] == [ver] call :git_ver & goto end
	if [%1] == [clear-history] call :git_clear_history & goto end
	if [%1] == [update-perms] call :git_update_perms & goto end

	call git.exe %1 %2 %3 %4 %5 %6 %7 %8 %9
	goto end

:main
	if [%1] == [] call :usage & goto end
	if [%1] == [help] call :usage & goto end
	if [%1] == [--help] call :usage & goto end
	if [%1] == [ls-all] call :list_known & goto end
	if [%1] == [ls-cloned] call :list_cloned & goto end
	if [%1] == [ls-uncloned] call :list_uncloned & goto end
	if [%1] == [ls-modified] call :list_modified & goto end
	if [%1] == [ls-unpushed] call :list_unpushed & goto end
	if [%1] == [ls-untracked] call :list_untracked & goto end
	if [%1] == [ls-double-tracked] call :list_double_tracked & goto end
	if [%1] == [clone] call :clone %2 %3 & goto end
	if [%1] == [clone-all] call :clone_all %2 %3 %4 %5 %6 %7 %8 %9 & goto end
	if [%1] == [unclone] call :unclone %2 & goto end
	if [%1] == [platform] call :platform & goto end
	call :git_cmd %*
	goto end

:begin
	setlocal
	set Z=%0
	pushd "%~dp0"
	if [%cd%\] == [%~dp0] goto callmain
	if [%cd%]  == [%~dp0] goto callmain
	call :usage Could not change dir to "%~dp0". & goto aftermain
:callmain
	call :main %*
:aftermain
	popd
	endlocal

:end
