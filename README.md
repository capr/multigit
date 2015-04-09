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
	$ touch foo.txt                # create empty file foo.txt
	$ touch bar.txt                # create empty file bar.txt
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

Notice the `-f` (force) when adding files to git. When creating a repo with
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

## How does it work?

Simply by telling git to clone all the repositories into a common
work tree. The git trees are kept in `.mgit/<repo>/.git` and the
work tree is always '.'.

This is such basic and useful functionality that it should
be built into `git clone` and `git init` really. As dead simple
as multigit is, it's still yet another script that you have to deploy.

## Simple? But it's a 500 lines script!

Don't worry about it, it's mostly fluff. The gist of it it's only 6 lines:

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

## How do I clone repos overlaid?

	$ mkdir project
	$ cd project
	$ mgit clone https://github.com/bob/foo
	$ mgit clone https://github.com/bob/bar

## But do I have to type the full URL every time?

	$ mgit baseurl https://github.com/bob/  # adds .mgit/bob.baseurl
	$ mgit clone bob/foo bob/bar            # adds .mgit/foo.origin and .mgit/bar.origin

Now that bob is known as a remote, and both foo's and bar's origins are
known too (they are set to `bob`), next time it will be enough to type
`mgit clone foo bar`. Which brings us to the next question...

## How do I create package collections?

	$ mgit init meta
	$ mgit meta add -f .mgit/bob.baseurl
	$ mgit meta add -f .mgit/foo.origin
	$ mgit meta add -f .mgit/bar.origin
	$ mgit meta commit -m "bob's place; foo and bar packages"

The meta repo like any other another repo (and it doesn't have to be
called meta either). It contains the information necessary to clone
foo and bar by name alone. So by cloning `meta` into your project
(by it's full url), you can then clone `foo` and `bar` with
`mgit clone foo bar`, or simply `mgit clone-all`.

## This will always clone master. How do I lock versions?

	$ mgit release 1.0 update     # adds .mgit/1.0.release

This creates (or updates) a list with currently checked out versions
of all repos, effectively recording a snapshot of the entire project.
This snapshot can later be restored with:

	$ mgit release 1.0 checkout

Needless to say, you can add these release files to your meta package,
just like with the .baseurl and .origin files before, so that other people
will be able to clone the project at that release point.

Another quick way to get a snapshot of the project without using .release
files is with:

	$ mgit --all ver

And later clone/checkout the repos with:

	$ mgit clone <the output of mgit --all ver>

## How does it use the current directory?

Just like git, mgit scans for a `.mgit` dir to find the root of your project,
and changes the current directory to that directory, and everything else
happens from there.

## Where is multigit used?

Multigit is the package manager for [luapower](https://luapower.com).
The [meta-package](https://github.com/luapower/luapower-repos) is just
like any other repo, and contains the list of packages to clone by name
and some multigit plugins specific to luapower.

## What multigit plugins?

Plugins allows extending multigit with project-specific scripts
that are exposed as multigit commands (like build scripts, etc.).
Plugin scripts can be included say, in the meta package of your project.
The way they work is very simple:

  * `mgit <repo> <command> ...` will try to run
    `.mgit/git-<command>.sh ...` with `$GIT_DIR` set properly
    and `$MULTIGIT_REPO` set to `<repo>`.

  * `mgit <command> ...` will try to run `.mgit/<command>.sh`.

  * `mgit help` will try to `cat .mgit/*.help`, which is where you should
    place the help section of the added commands.

Look at [luapower-repos](https://github.com/luapower/luapower-repos)
for a real-world example of this.

## Related efforts

The most similar project that I was able to find is [vcsh](https://github.com/RichiH/vcsh).
It even has a [video presentation](http://mirror.as35701.net/video.fosdem.org//2012/lightningtalks/vcsh.webm).
