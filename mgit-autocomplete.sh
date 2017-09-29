#!/bin/bash

__array_contains () {
		local seeking=$1; shift
		local in=1
		for element; do
				if [[ $element == $seeking ]]; then
						in=0
						break
				fi
		done
		echo $in
		}

_mgit()
		{
		cur=${COMP_WORDS[COMP_CWORD]}
		local nocomp="which remove"

		if [[ $(mgit ls) != $(cd /;mgit ls) ]]
		then
				repos=$(mgit ls)
		else
				repos=()
		fi

		if [[ ${#COMP_WORDS[@]} -gt 2 ]]
		then
				if [[ $(__array_contains ${COMP_WORDS[1]} $nocomp) -eq 0 ]]
				then
						if [[ ${COMP_WORDS[1]} == "remove" ]]
						then
								complete="$repos"
						else
								return #fall back to bash file autocomplete or don't return anything
						fi
				elif [[ $(__array_contains ${COMP_WORDS[1]} $repos) -eq 0 ]]
				then
						cword=$((${#COMP_WORDS[@]}-1))
						words=(git --git-dir=".mgit/${COMP_WORDS[1]}/.git" ${COMP_WORDS[@]:2})
						prev=${words[$(($cword-1))]}
						COMP_WORDS=${words[@]}

						unset COMPREPLY
						__git_main
						unset words cword prev cur
						return
				else
						complete=""
				fi
		else
				local default=" init
								remove
								ls
								ls-all
								ls-uncloned
								ls-untracked
								ls-double-tracked
								ls-tracked
								which
								ls-modified
								status
								ls-unpushed
								clone
								clone-all
								clone-release
								origin
								baseurl
								"

				__gitcomp "$repos $default" #handles trailing spaces yay!
				return
		fi
		COMPREPLY=( $(compgen -W "$complete" -- $cur) )
		}

complete -o bashdefault -o default -o nospace -F _mgit mgit

