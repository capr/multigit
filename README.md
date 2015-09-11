# multigit

#### layered git repositories
<sub>Writen by Cosmin Apreutesei. **Public Domain**.</sub><br>
<sub>Tested on **Linux**, **Windows** and **OSX**</sub>

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

Some examples where this combination of change management
and module management could be useful:

  * manage customizations made to a web app in a separate repository.
  * putting your home directory under source control.
  * package and/or config manager for a Linux distro.

## How do I install it?

Multigit is a simple shell script with no dependencies. You can either
put it somewhere in your PATH, or you can clone it everywhere
you want to create a multigit project in, and call it as `./mgit`
(or `mgit` on Windows).

## How do I use it?

Let's see a bare bones example:

	$ mkdir project
	$ cd project

	$ mgit init foo                # create layered repo foo
	$ mgit init bar                # create layered repo bar
	$ mgit ls                      # list layered repos
	foo
	bar

	$ echo > foo.txt               # create file foo.txt
	$ echo > bar.txt               # create file bar.txt
	$ mgit foo add -f foo.txt      # add foo.txt to project foo
	$ mgit bar add -f bar.txt      # add bar.txt to project bar
	$ mgit foo commit -m "init"    # commit on foo
	$ mgit bar commit -m "init"    # commit on bar

	$ ls
	foo.txt bar.txt                # foo.txt and bar.txt are in the same dir
	$ mgit foo ls-files
	foo.txt                        # but project foo only tracks foo.txt
	$ mgit bar ls-files
	bar.txt                        # and project bar only tracks bar.txt

Note the `-f` (force) when adding files to git. When creating a repo with
`mgit init foo`, the `.gitignore` file for foo is set to
`.mgit/foo.exclude` which defaults to `*`, which means that
all files are ignored by default, hence the need to add them with `-f`.
This is to prevent accidentally adding files of other projects with
`git add -A` and ending up with multiple projects tracking the same file.
To recover the convenience of `git -A` and the correct reporting of
untracked files, change the exclude files and add patterns that are
appropriate to each repo. Given that all repos now share the same
namespace, you need to be explicit about which parts of that namespace
are "reserved" for which repos.

You can use git direcly on your layered repos with a subshell:

	$ mgit foo
	Entering subshell: git commands will affect the repo 'foo'.
	Type `exit' to exit subshell.
	A  foo.txt

	[foo] $ git ls-files
	foo.txt
	[foo] $ exit
	$

Or you can type git commands directly without a subshell:

	$ mgit foo ls-files
	foo.txt

Or you can ditch multigit entirely and go bare git:

	$ export GIT_DIR=.mgit/foo/.git
	$ git ls-files
	foo.txt

## How do I clone repositories?

	$ mkdir project
	$ cd project

	$ mgit clone https://github.com/bob/foo
	$ mgit clone https://github.com/bob/bar

This will clone both repos into the current directory
(there's no "target directory" arg).

## But do I have to type the full URL every time?

	$ mgit baseurl https://github.com/bob/  # adds .mgit/bob.baseurl
	$ mgit clone bob/foo bob/bar            # adds .mgit/foo.origin and .mgit/bar.origin

Now that bob is _registered_ as a remote, and both foo's and bar's origins
are registered too (they are set to `bob`), next time it will be enough
to type `mgit clone foo bar`. Which brings us to the next question...

## How do I manage module collections?

Every time you clone a repo with `mgit clone`, a file `.mgit/foo.origin`
is created which contains the origin url of that repo, which allows you
to clone it by name alone. These files are not tracked by default,
they're just sitting there, but there's nothing stopping you from
creating a "meta" repo and start tracking them:

	$ mgit init meta
	$ mgit meta add -f .mgit/bob.baseurl   # add bob's baseurl to meta
	$ mgit meta add -f .mgit/foo.origin    # add foo's origin to meta
	$ mgit meta add -f .mgit/bar.origin    # add bar's origin to meta
	$ mgit meta commit -m "bob's place; foo and bar modules"

> The meta repo is like any other layered repo, it just so happens that it
tracks files from `.mgit` (and it doesn't have to be called meta either,
and it doesn't have to be the _only_ repo containing meta-information).

Maintaining a `meta` repo for a project allows the users of that project
to clone the meta repo and then clone all other repos
with `mgit clone-all` (and list them with `mgit ls-all`).
This makes for a simple way to manage and share module collections
that later can be cloned back wholesale.

Note that repos created with `mgit init foo` don't create an origin file.
You can add that yourself with `mgit origin foo <url>`.

## But this will always clone master. How do I lock versions?

	$ mgit release 1.0 update     # adds .mgit/1.0.release

This creates (or updates) a list with currently checked out versions
of all repos, effectively recording a snapshot of the entire project.
This snapshot can later be restored with:

	$ mgit clone-release 1.0

> Note: Existing repos will have to be removed first. This command
will refuse to overwrite them. Also, this will not create branches.
Your repos will be in "detached HEAD state". You can take it from there
with git, eg. with `mgit --all checkout -b release-1.0`.

Needless to say, you can add the .release file to your meta repo too,
just like with the .baseurl and .origin files before, so that other people
will be able to clone the project at that specific release point.

Another quick way to get a snapshot of the project without using .release
files is with:

	$ mgit --all ver
	foo=701d080 bar=0fefd96

And later clone the repos with:

	$ mgit clone foo=701d080 bar=0fefd96

Tag releases can be made with:

	$ mgit release 1.0 update tag

Tag releases only record the current tag as opposed to the exact
full version of the packages. This allows you to make stable releases
even when some packages are "unstable" (i.e. they contain commits above the
latest tag). It also allows the controversial practice of updating a tag's
target without having to make a new release.

## What else can it do?

command                               | description
------------------------------------- | --------------------------------------
`mgit ls-modified`                    | list modified files across all repos
`mgit ls-unpushed`                    | list repos ahead of origin
`mgit ls-untracked`                   | list files untracked by any repo
`mgit ls-double-tracked`              | list files tracked by multiple repos
`mgit remove [--dry] REPO ...`        | remove repos from disk


There's more stuff, type `mgit` to see.

## How does this work anyway?

Simply by telling git to clone all the repositories into a common
work tree. The git trees are kept in `.mgit/<repo>/.git` and the
work tree is always '.'.

This is such basic and useful functionality that it should
be built into `git clone` and `git init` really. As dead simple
as multigit is, it's still yet another script that you have to deploy.

## Simple? But it's a 600 lines script!

Don't worry about it, it's mostly fluff. The gist of it is only 6 lines:

mgit init foo:

	mkdir -p .mgit/foo
	export GIT_DIR=.mgit/foo/.git
	git init                                                  # create .mgit/foo/.git
	git config --local core.worktree ../../..                 # relative to GIT_DIR
	git config --local core.excludesfile .mgit/foo.exclude    # instead of .gitignore
	[ -f .mgit/foo.exclude ] || echo '*' > .mgit/foo.exclude  # "ignore all"

mgit foo ls-files:

	export GIT_DIR=.mgit/foo/.git    # set git to work on foo
	git ls-files                     # list files of foo

## What's its relation to the current directory?

Just like git, mgit scans the current directory and its parents for
a `.mgit` dir, and if found, it sets the current directory to that,
and everything else happens from there, except starting a subshell
and executing git commands which run in the current directory.

## Where is multigit used?

Multigit is the package manager for [luapower](https://luapower.com).
The [meta-package](https://github.com/luapower/luapower-repos) contains
the list of packages in the distribution and a few handy multigit plugins
specific to luapower.

## What multigit plugins?

Plugins allows extending multigit with project-specific scripts
that are exposed as multigit commands (like build scripts, etc.).
Plugin scripts can be included say, in the meta package of your project.
The way they work is very simple:

  * `mgit <repo> <command> ...` will try to run
    `.mgit/git-<command>.sh ...` with `$GIT_DIR` set properly,
	 `$MULTIGIT_REPO` set to `<repo>`, `$PWD0` set to the
	 invocation path and current directory set to one directory where
	 the `.mgit` directory was found.

  * `mgit <command> ...` will try to run `.mgit/<command>.sh`.

  * `mgit help` will try to `cat .mgit/*.help`, which is where you should
    place the help section of the added commands.

Look at [luapower-repos](https://github.com/luapower/luapower-repos)
for a real-world example of this.

## Environment

Multigit will use the following environment variables when performing
various tasks:

  * `$MULTIGIT_FETCH_OPTS` will be expanded and passed to `git fetch`
  * `$MULTIGIT_INIT_OPTS` will be expanded and passed to `git init`

## Limitations

  * No way to specify a different branch when cloning (must switch it after).
  * No way to specify a different branch when making releases.
  * No way to register multiple remotes for the same repo and specify
  the remote when cloning.

## Related efforts

There is a very similar project called [vcsh](https://github.com/RichiH/vcsh).
It even has a [video presentation](http://mirror.as35701.net/video.fosdem.org//2012/lightningtalks/vcsh.webm),
check it out.
