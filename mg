#!/bin/sh

usage() {
	[ "$1" ] && {
		echo
		echo "ERROR: $1"
		echo
		exit
	}
	echo
	echo " Multigit 1.0 - git wrapper for working with overlaid repos."
	echo " Written by Cosmin Apreutesei. Public Domain."
	echo " Developed at https://github.com/capr/multigit"
	echo
	echo " USAGE: $ZERO ..."
	echo
	echo "   ls-all                     list all known packages"
	echo "   ls-uncloned                list not yet cloned packages"
	echo "   ls-cloned                  list cloned packages"
	echo "   ls-modified                list packages that were modified locally"
	echo "   ls-unpushed                list packages that are ahead of origin"
	echo "   ls-untracked               list files untracked by any repo"
	echo "   ls-double-tracked          list files tracked by multiple repos"
	echo "   clone [origin/]pkg|url ... clone packages"
	echo "   clone-all [fetch-options]  clone all uncloned packages"
	echo "   unclone pkg ...            remove cloned packages from disk (!)"
	echo "   pkg|--all up [message]     add/commit/push combo"
	echo "   pkg|--all uptag            update current tag to point to current commit"
	echo "   pkg|--all ver[sion]        show package version"
	echo "   pkg|--all clear-history    clear the history of the current branch (!)"
	echo "   pkg|--all update-perms     chmod+x all .sh files in package (in git)"
	echo "   pkg|--all make-symlinks    make symbolic links in .multigit/pkg"
	echo "   pkg|--all make-hardlinks   make hard links in .multigit/pkg"
	echo "   pkg|--all command ...      execute any git command on a package repo"
	echo "   pkg                        start a git subshell for a package repo"
	echo "   [help|--help]              show this screen"
	echo
	exit
}

list_known() {
	(cd .multigit && \
	for f in *.origin; do
		echo "${f%.origin}"
	done)
}

list_cloned() {
   (cd .multigit && \
	for f in *; do
		[ -d "$f/.git" ] && echo "$f"
	done)
}

list_uncloned() {
	(cd .multigit
	for f in *.origin; do
		f=${f%.origin}
		[ ! -d "$f/.git" ] && echo $f
	done)
}

git_cmd_all() {
	for package in `list_cloned`; do
		git_cmd "$package" "$@"
	done
}

list_modified() {
	git_cmd_all status -s
}

list_unpushed() {
	local cmd="git rev-list HEAD...origin/master --count"
	for package in `list_cloned`; do
		[ "$(GIT_DIR=".multigit/$package/.git" $cmd)" != "0" ] && echo "$package"
	done
}

tracked_files() {
	(git ls-files
	for package in `list_cloned`; do
		GIT_DIR=".multigit/$package/.git" git ls-files
	done) | sort | uniq $1
}

existing_files() {
	find * -type f | sort | uniq
}

list_untracked() {
	tracked=$$-1.tmp
	existing=$$-2.tmp
	tracked_files > $tracked
	existing_files > $existing
	comm -23 $existing $tracked
	rm $tracked $existing
}

list_double_tracked() {
	tracked_files -d
}

clone_all() {
	export MULTIGIT_FETCH_OPTS="$@"
	for package in `list_uncloned`; do
		./git clone "$package"
	done
}

clone_one() {
	local arg=$1
	local name
	local origin
	local rorigin
	local url

	# trim arg
	arg=${arg# *}
	arg=${arg%* }

	# check if the arg is a full url or just `[origin/]name`
	if [ "${arg#*:}" != "$arg" ]; then
		url=$arg
		origin=$arg
		name=${url##*/}
		name=${name%.git}
	else
		name=${arg##*/}
		origin=${arg%/*}
		[ "$origin" = "$arg" ] && origin=""
	fi

	# check that the name does not contain spaces or is made of slashes
	[ "$arg" = "$1" -a "$name" ] || \
		usage "Invalid package name \"$1\"."

	# check that the package is not already cloned
	[ -d ".multigit/$name/.git" ] && {
		echo "ERROR: Already cloned: \"$name\"."
		return
	}

	# check for a registered origin
	[ -f ".multigit/$name.origin" ] && \
		rorigin=$(cat .multigit/$name.origin)

	# decide the origin
	if [ "$origin" ]; then
		[ "$origin" = "$rorigin" ] || \
			echo "Cloning \"$name\" from different origin \"$origin\" (was \"$rorigin\")."
	else
		origin=$rorigin
		[ "$origin" ] || {
			echo "ERROR: Missing origin for \"$name\": \".multigit/$name.origin\"."
			return
		}
	fi

	# find the origin url
	if [ ! "$url" ]; then
		if [ -f ".multigit/$origin.baseurl" ]; then
			local baseurl=$(cat .multigit/$origin.baseurl)
			url=$baseurl$name
		else
			# assume the origin on file is a full url: check if it is
			if [ "${origin#*:}" != "$origin" ]; then
				url=$origin
			else
				echo "ERROR: Unknown origin: \"$origin\"."
				return
			fi
		fi
	fi

	# set the .gitignore file for multigit on the first clone operation.
	git config core.excludesfile .multigit/.exclude

	# finally, clone the package
	mkdir -p ".multigit/$name"
	export GIT_DIR=".multigit/$name/.git"
	git init
	git config --local core.worktree ../../..
	git config --local core.excludesfile ".multigit/$name.exclude"
	git remote add origin $url
	git fetch $MULTIGIT_FETCH_OPTS || {
		rm -rf ".multigit/$name/.git"
		echo "ERROR: git fetch error."
		return
	}
	git branch --track master origin/master
	git checkout

	# make an "exclude-all" exclude file if one is not present
	[ -f ".multigit/$name.exclude" ] || echo '*' > ".multigit/$name.exclude"

	# if fetch was successful, (re)register the origin for the package
	if [ "$origin" != "$rorigin" ]; then
		if [ "$rorigin" ]; then
			echo "NOTE: Updating origin for \"$name\": \"$origin\" (was \"$rorigin\")"
		else
			echo "NOTE: Registering origin for \"$name\": $origin ($url)"
		fi
		echo $origin > ".multigit/$name.origin"
	fi
}

clone() {
	[ "$1" ] || usage "Package name expected."
	if [ $# = 1 ]; then
		clone_one "$@"
	else
		while [ $# != 0 ]; do
	   	clone_one "$1"
	   	shift
	   done
	fi
}

unclone_one() {
	[ -d ".multigit/$1/.git" ] || {
		echo "ERROR: package not found \"$1\"."
		return
	}

	# get tracked files for this package
	files="$(GIT_DIR=".multigit/$1/.git" git ls-tree -r --name-only HEAD)" || {
		echo "ERROR: could not get files for \"$1\"."
		return
	}

	# remove files
	for file in $files; do
		rm "$file"
	done

	# remove empty directories
	for file in $files; do
		echo "$(dirname "$file")"
	done | uniq | while read dir; do
		[ "$dir" != "." ] && /bin/rmdir -p "$dir" 2>/dev/null
	done

	# remove the git dir
	rm -rf ".multigit/$1/.git"
	rmdir ".multigit/$1"

	echo "Removed: \"$1\"."
}

unclone() {
	[ "$1" ] || usage "Package name expected."
	[ "$GIT_DIR" ] && usage "Refusing to unclone from a subshell."
	if [ $# = 1 ]; then
		unclone_one "$@"
	else
		while [ $# != 0 ]; do
	   	unclone_one "$1"
	   	shift
	   done
	fi
}

git_shell() {
	echo "Entering subshell: git commands will work on package \"$MULTIGIT_PACKAGE\"."
	echo "Type \`exit' to exit subshell."
	git status -s
	echo
	if [ "$OSTYPE" = "msys" ]; then
		export PROMPT="[$MULTIGIT_PACKAGE] \$P\$G"
		exec "$COMSPEC" /k
	else
		export PS1="[$MULTIGIT_PACKAGE] \u@\h:\w\$ "
		exec "$SHELL" -i
	fi
}

git_up() {
	msg="$1"
	[ "$msg" ] || msg="unimportant"
	git add -A
	git commit -m "$msg"
	git push
}

git_uptag() {
	local tag="$(git describe --tags --abbrev=0)"
	[ "$tag" ] || usage "No current tag to update. Make a tag first."
	git tag -f "$tag"
	git push -f --tags
}

git_ver() {
	printf "%-20s" "$MULTIGIT_PACKAGE"
	git describe --tags --long --always
}

git_clear_history() {
	local branch="$(git rev-parse --abbrev-ref HEAD)"
	git checkout --orphan delete_me
	git add -A
	git commit -m "init (history cleared)"
	git branch -D "$branch"
	git branch -m "$branch"
}

git_update_perms() {
	git ls-files | \
		while read f; do
			[ "${f##*.}" = "sh" ] && \
				git update-index --chmod=+x "$f"
		done
}

git_remove_links() {
	[ "$OSTYPE" = "msys" ] && "Not for Windows."
	([ "$MULTIGIT_PACKAGE" ] && cd ".multigit/$MULTIGIT_PACKAGE" || exit 1
	find . ! -path './.git/*' ! -path './.git' ! -path '.' -exec rm -rf {} \; 2>/dev/null)
}
git_make_hardlinks() {
	git_remove_links
	git ls-files | while read f; do
		mkdir -p "$(dirname ".multigit/$MULTIGIT_PACKAGE/$f")"
		ln -f "$f" ".multigit/$MULTIGIT_PACKAGE/$f"
	done
}
git_make_symlinks() {
	git_remove_links
	git ls-files | while read f; do
		mkdir -p "$(dirname ".multigit/$MULTIGIT_PACKAGE/$f")"
		ln -sf "$PWD/$f" ".multigit/$MULTIGIT_PACKAGE/$f"
	done
}

git_cmd() {
	pkg="$1"; shift

	export GIT_DIR=".multigit/$pkg/.git"
	export MULTIGIT_PACKAGE="$pkg"
	[ -d "$GIT_DIR" ] || usage "Unknown package: \"$pkg\"."

	[ "$1" ] || { git_shell; return; }
	[ "$1" = "up" ] && { git_up "$2"; return; }
	[ "$1" = "uptag" ] && { git_uptag; return; }
	[ "$1" = "ver" -o "$1" = "version" ] && { git_ver; return; }
	[ "$1" = "clear-history" ] && { git_clear_history; return; }
	[ "$1" = "update-perms" ] && { git_update_perms; return; }
	[ "$1" = "make-symlinks" ] && { git_make_symlinks; return; }
	[ "$1" = "make-hardlinks" ] && { git_make_hardlinks; return; }

	git "$@"
}

[ "$ZERO" ] || ZERO="$0" # for wrapping
cd "${0%mg}" || usage "Could not change dir to \"${0%mg}\"."

[ -z "$1" -o "$1" = "help" -o "$1" = "--help" ] && usage
[ "$1" = "ls-all" ] && { list_known; exit; }
[ "$1" = "ls-cloned" ] && { list_cloned; exit; }
[ "$1" = "ls-uncloned" ] && { list_uncloned; exit; }
[ "$1" = "ls-modified" ] && { list_modified; exit; }
[ "$1" = "ls-unpushed" ] && { list_unpushed; exit; }
[ "$1" = "ls-untracked" ] && { list_untracked; exit; }
[ "$1" = "ls-double-tracked" ] && { list_double_tracked; exit; }
[ "$1" = "clone" ] && { shift; clone "$@"; exit; }
[ "$1" = "clone-all" ] && { shift; clone_all "$@"; exit; }
[ "$1" = "unclone" ] && { shift; unclone "$@"; exit; }
[ "$1" = "--all" ] && {
	shift
	[ "$@" ] || usage "Refusing to start a subshell for each package."
	git_cmd_all "$@"
	exit
}

git_cmd "$@"
