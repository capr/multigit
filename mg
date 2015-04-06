#!/bin/sh

usage() {
	[ "$1" ] && {
		echo
		echo "ERROR: $1"
		echo
		exit
	}
	echo
	echo " MultiGit 1.0 - git wrapper for working with overlaid repos."
	echo " Written by Cosmin Apreutesei. Public Domain."
	echo " Developed at https://github.com/capr/multigit"
	echo
	echo " USAGE: mg ..."
	echo
	echo "   ls                          list cloned repos"
	echo "   ls-all                      list all known repos"
	echo "   ls-uncloned                 list all known but not cloned repos"
	echo "   ls-modified                 list repos that were modified locally"
	echo "   ls-unpushed                 list repos that are ahead of origin"
	echo "   ls-untracked                list files untracked by any repo"
	echo "   ls-double-tracked           list files tracked by multiple repos"
	echo
	echo "   clone [origin/]repo|url ... clone repos"
	echo "   clone-all [fetch-options]   clone all uncloned repos"
	echo "   unclone repo ...            remove cloned repos from disk (!)"
	echo
	echo "   baseurl [origin] [url]      get or set the baseurl for an origin"
	echo "   origin [repo] [origin|url]  get or set the default origin for a repo"
	echo
	echo "   repo|--all up [message]     add/commit/push combo"
	echo "   repo|--all uptag            update current tag to point to current commit"
	echo "   repo|--all ver[sion]        show repo version"
	echo "   repo|--all clear-history    clear the history of the current branch (!)"
	echo "   repo|--all update-perms     git-chmod +x all .sh files in repo"
	echo "   repo|--all make-symlinks    make symbolic links in .multigit/repo"
	echo "   repo|--all make-hardlinks   make hard links in .multigit/repo"
	echo "   repo|--all command ...      execute any git command on a repo"
	echo "   repo                        start a git subshell for a repo"
	echo
	echo "   [help|--help]               show this screen"
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
	for repo in `list_cloned`; do
		git_cmd "$repo" "$@"
	done
}

list_modified() {
	git_cmd_all status -s
}

list_unpushed() {
	local cmd="git rev-list HEAD...origin/master --count"
	for repo in `list_cloned`; do
		[ "$(GIT_DIR=".multigit/$repo/.git" $cmd)" != "0" ] && echo "$repo"
	done
}

tracked_files() {
	(git ls-files
	for repo in `list_cloned`; do
		GIT_DIR=".multigit/$repo/.git" git ls-files
	done) | sort | uniq $1
}

existing_files() {
	find * -type f | grep -v \.tmp$ | sort | uniq
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
	for repo in `list_uncloned`; do
		./mg clone "$repo"
	done
}

clone_one() {
	local arg=$1
	local name
	local origin
	local rorigin
	local url

	# spaces not allowed
	arg=${arg//[[:blank:]]/}

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
		usage "Invalid repo name \"$1\"."

	# check that the repo is not already cloned
	[ -d ".multigit/$name/.git" ] && {
		echo "ERROR: Already cloned: \"$name\"."
		return
	}

	# check for a registered origin
	[ -f ".multigit/$name.origin" ] && \
		rorigin=$(cat .multigit/$name.origin)

	# decide the origin
	if [ "$origin" ]; then
		[ -z "$rorigin" -o "$origin" = "$rorigin" ] || \
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
				echo "ERROR: Unknown origin: \"$origin\" for \"$name\"."
				return
			fi
		fi
	fi

	# set the .gitignore file for multigit on the first clone operation.
	git config core.excludesfile .multigit/.exclude

	# finally, clone the repo
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

	# if fetch was successful, (re)register the origin for the repo
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
	[ "$1" ] || usage "Repo name expected."
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
		echo "ERROR: repo not found \"$1\"."
		return
	}

	# get tracked files for this repo
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
	rm -rf ".multigit/$1/"

	echo "Removed: \"$1\"."
}

unclone() {
	[ "$1" ] || usage "Repo name expected."
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

baseurl() {
	[ "$1" ] || {
		for f in .multigit/*.baseurl; do
			f=${f#.multigit/}
			f=${f%.baseurl}
			printf "%-20s %s\n" "$f" "$(baseurl "$f")"
		done
		return
	}
	local origin=$1
	local url=$2
	# spaces not allowed
	origin=${origin//[[:blank:]]/}
	url=${url//[[:blank:]]/}
	[ -z "$1" -o "$1" != "$origin" ] && usage "Invalid origin name \"$1\"."
	[ "$2" -a "$2" != "$url" ] && usage "Invalid baseurl \"$2\"."
	if [ "$url" ]; then
		echo "$url" > ".multigit/$origin.baseurl"
	else
		cat ".multigit/$origin.baseurl"
	fi
}

origin() {
	[ "$1" ] || {
		for f in .multigit/*.origin; do
			f=${f#.multigit/}
			f=${f%.origin}
			printf "%-20s %s\n" "$f" "$(origin "$f")"
		done
		return
	}
	local repo=$1
	local origin=$2
	# spaces not allowed
	repo=${repo//[[:blank:]]/}
	origin=${origin//[[:blank:]]/}
	[ -z "$1" -o "$1" != "$repo" ] && usage "Invalid repo name \"$1\"."
	[ "$2" -a "$2" != "$origin" ] && usage "Invalid origin \"$2\"."
	if [ "$origin" ]; then
		echo "$origin" > ".multigit/$repo.origin"
	else
		cat ".multigit/$repo.origin"
	fi
}

git_shell() {
	echo "Entering subshell: git commands will work on repo \"$MULTIGIT_REPO\"."
	echo "Type \`exit' to exit subshell."
	git status -s
	echo
	if [ "$OSTYPE" = "msys" ]; then
		export PROMPT="[$MULTIGIT_REPO] \$P\$G"
		exec "$COMSPEC" /k
	else
		export PS1="[$MULTIGIT_REPO] \u@\h:\w\$ "
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
	printf "%-20s" "$MULTIGIT_REPO"
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
	[ "$OSTYPE" = "msys" ] && usage "Not for Windows."
	([ "$MULTIGIT_REPO" ] && cd ".multigit/$MULTIGIT_REPO" || exit 1
	find . ! -path './.git/*' ! -path './.git' ! -path '.' -exec rm -rf {} \; 2>/dev/null)
}
git_make_hardlinks() {
	git_remove_links
	git ls-files | while read f; do
		mkdir -p "$(dirname ".multigit/$MULTIGIT_REPO/$f")"
		ln -f "$f" ".multigit/$MULTIGIT_REPO/$f"
	done
}
git_make_symlinks() {
	git_remove_links
	git ls-files | while read f; do
		mkdir -p "$(dirname ".multigit/$MULTIGIT_REPO/$f")"
		ln -sf "$PWD/$f" ".multigit/$MULTIGIT_REPO/$f"
	done
}

git_cmd() {
	repo="$1"; shift
	export GIT_DIR=".multigit/$repo/.git"
	export MULTIGIT_REPO="$repo"
	[ -d "$GIT_DIR" ] || usage "Unknown repo: \"$repo\"."
	case "$1" in
		up)             git_up "$2" ;;
		uptag)          git_uptag ;;
		ver)            git_ver ;;
		version)        git_ver ;;
		clear-history)  git_clear_history ;;
		update-perms)   git_update_perms ;;
		make-symlinks)  git_make_symlinks ;;
		make-hardlinks) git_make_hardlinks ;;
		"")             git_shell ;;
		*)              git "$@" ;;
	esac
	export GIT_DIR=
	export MULTIGIT_REPO=
}

cd "${0%mg}" || usage "Could not change dir to \"${0%mg}\"."

case "$1" in
	"")           usage ;;
	help)         usage ;;
	--help)       usage ;;
	ls)           list_cloned ;;
	ls-all)       list_known ;;
	ls-uncloned)  list_uncloned ;;
	ls-modified)  list_modified ;;
	ls-unpushed)  list_unpushed ;;
	ls-untracked) list_untracked ;;
	ls-double-tracked) list_double_tracked ;;
	clone)   shift; clone "$@" ;;
	unclone) shift; unclone "$@" ;;
	baseurl) shift; baseurl "$@" ;;
	origin)  shift; origin "$@" ;;
	--all)
		shift
		[ "$@" ] || usage "Refusing to start a subshell for each repo."
		git_cmd_all "$@"
		;;
	*) git_cmd "$@" ;;
esac
