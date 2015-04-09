# multigit

Git wrapper for working with overlaid git repositories.
Writen by Cosmin Apreutesei. Public Domain.

Multigit allows you to check out multiple git repositories over a
common directory and provides simple tools that let you continue
to use git as before, without multigit getting in your way.

It is useful for projects which are made of different components
that are developed separately, but which need to deploy files
in different parts of the directory structure of the project.

This cannot be done using git submodules or git subtrees, which
only allow subprojects to deploy files in their own subdirectory.
Multigit allows subprojects to deploy files in any directory of the
project, similar to a union filesystem, where each repository is a layer.

## How does it work?

Simply by telling git to clone all the repositories into a common
work tree. The git trees are kept in `.multigit/<repo>/.git` and the
work tree is always '.'.

This is such basic and such useful functionality that it should
be built into `git clone` and `git init` really. As dead simple
as multigit is, it's still yet another script that you have to deploy.

## Simple? But it's a 500 lines script!

Don't worry about it, it's mostly fluff. The gist of it it's only 6 lines:

git init foo:

	mkdir -p .multigit/foo
	export GIT_DIR=.multigit/foo/.git
	git init
	git config --local core.worktree ../../..
	git config --local core.excludesfile .multigit/foo.exclude
	[ -f .multigit/foo.exclude ] || echo '*' > .multigit/foo.exclude

git foo:

	GIT_DIR=.multigit/foo/.git git

## How do I use it?

Let's see a bare bones example:

	$ mkdir project
	$ cd project
	$ mgit init foo                # create layered subproject foo
	$ mgit init bar                # create layered subproject bar
	$ touch foo.txt                # create empty file foo.txt
	$ touch bar.txt                # create empty file bar.txt
	$ mgit foo add -f foo.txt      # add foo.txt to project foo
	$ mgit bar add -f bar.txt      # add bar.txt to project bar
	$ mgit foo commit -m "init"    # commit on foo
	$ mgit bar commit -m "init"    # commit on bar
	$ ls
	foo.txt bar.txt                # both foo.txt and bar.txt share the same dir
	$ mgit foo ls-files
	foo.txt                        # but project foo only tracks foo.txt
	$ mgit bar ls-files
	bar.txt                        # while project bar only tracks bar.txt

Notice the `-f` (force) when adding files to git. When creating a repo with
`mgit init foo`, the `.gitignore` file for foo is set to
`.multigit/foo.exclude` which defaults to `*`, which means that
all files are ignored by default, hence the need to add them with `-f`.
This is to prevent accidentally adding files of other projects with
`git add -A` and ending up with multiple projects tracking the same file.
To recover the convenience of `git -A` and the correct reporting of
untracked files, change the exclude files and add patterns that are
appropriate to each repo. Given that all repos now share the same
namespace, you need to be explicit about which parts of that namespace
are "reserved" for which repo.

## Who uses it?

Multigit is the package manager for [luapower](https://luapower.com).
The [meta-package](https://github.com/luapower/luapower-repos) contains
the list of packages to clone by name and some multigit plugins specific
to luapower.

## What multigit plugins?

Plugins allows extending multigit with project-specific scripts
that are exposed as multigit commands (like build scripts, etc.).
Plugin scripts can be included in any of the repo(s) of your project.

`mgit <repo> <command> ...` will try to run
`.multigit/git-<command>.sh ...` with `$GIT_DIR` set properly
and `$MULTIGIT_REPO` set to `<repo>`.

`mgit <command> ...` will try to run `.multigit/<command>.sh`.

`mgit help` will try to `cat .multigit/*.help`, which is where you should
place the help section of the added commands.

Look at [luapower-repos](https://github.com/luapower/luapower-repos)
for a real-world example of this.
