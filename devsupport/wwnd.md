# What Would nyarly Do?

## Basic Tools

The development environment in this repo
is pretty opinionated.
Without too much effort it should be adaptable
to other approaches.

With your workstation set up this way,
you'll be able to
install the tools for individual software projects
and make sure that you've got the right versions
of your toolchain installed as you switch between projects.
(Or even branches of the same project!)
All those requirements will be recorded
alongside the code that needs those tools,
and we save a ton of hassle working through a whole set up procedure.

This is kind of like rbenv, or pyenv, or...
but for everything, including PostgreSQL
and tools like process-compose -
you can have the best of breed, why limit yourself to
one language's ecosystem?

To get to this utopian future,
this set up relies on a few basic tools,
to manage that description of requirements,
and to set them up automatically as you
switch to the project directory
or change branches.

If you don't have all of
`nix`, `direnv`, `lorri` and tmux
already installed on your workstation,
and you'd like to try them out,
here's a guide to doing that.
The first 3 provide progressive benefits,
and we'll talk about what those are,
so that you can adopt them gradually
if that's your preference.

Plus Tmux is an indespensible tool for managing complex workspaces.

## Nix

The first thing to set up is Nix.

Nix is a Unix packaging solution
that's been getting traction in recent years.
It can work either as a whole OS install (like Ubuntu),
or as a complement to the packaging system
of a host OS, analogous to Homebrew.

Nix has a number of nice properties,
including that its installation configurations are deterministic,
meaning that I can write up "here's what we need for this project"
and you can run a command and get everything set up at once.

I'm going to assume that
if you already knew you wanted to use Nix as your OS,
you'd be doing that already.
So let's just set up Nix as an ancillary package manager.

For that, consider either
[https://nixos.org/download/]
or
[https://determinate.systems/nix-installer/].

You'll need to ensure that you've enabled the `nix-command` and `flakes`
"experimental" features of Nix.

Once you have a flake-enabled Nix install,
you should be able to run `nix develop`
and see how what tools this project sets up.
The first time you run this command
(and the first time after depenedencies change)
there'll be a little wait while it installs
(and possibly compiles)
the whole toolchain.
Subsequent runs will be much faster.
When it's done, you'll be in a subshell with
all the tools needed in your $PATH and ready to use.
When you're done, you can `<Ctrl-D>`
to get out of it -
you'll notice that things like `cargo` and `elm`
aren't available anymore from the workspace.
(Unless, of course, you already have them installed locally.)


You might also look at the `flake.nix` file in this repo:
that's the description of the tools needed,
for _this_ project
and where to get them.

## Global Requirements

Now we're going to add a few tools to your workstation.

`direnv` watches the directory your terminal is in and sets environment variables.
Since it can update your `PATH` it can also make sure that certain programs
are availabe on a per-directory basis,
which makes it incredibly powerful,
despite its simplicity.
The `envrc.example`, if you copy it to `.envrc`
and run `direnv allow`
(please do examine the file before you do so:
direnv essentially runs it as a shell script,
and anything could be there!)
will (effectively) run `nix develop`
and update the current shell's PATH with the tools in the `flake.nix`
_and_ remove them from the PATH when you leave the directory.

You could change the `.envrc` not to use `lorri`
(there are direction in the `example.envrc`)
but you'll find that the `nix develop` delay happens before printing your shell prompt.
For the most part, that will only happen the first time you use the project...
or when development dependencies change.
It's not a big deal, but it can break your flow.
`lorri` works with `direnv` to help smooth out
those install delays -
it sends the install and build process into the background,
so that your prompt always returns right away.
With the right `direnv` configuration, it'll do the `nix develop` for you,
install everything in the background,
and then make the tools available on your `PATH` when they're ready.

Finally, `tmux` is a "terminal multiplexer" that lets you
create and manipulate sub-windows of your terminal,
so you can have multiple shells running next to each other.
This is incredibly handy when you want to have the manual up
and run a tool in another shell,
or edit in one shell,
and test the code you're editing in another.

Anyway, we're going to install all of those globally with

```shell
> nix profile install 'nixpkgs#direnv' 'nixpkgs#lorri' 'nixpkgs#tmux'
```

From there, `direnv` requires a little
[installation process](https://github.com/direnv/direnv/blob/master/docs/hook.md)
for your shell.

Likewise, Lorri needs a daemon to be set up.
You can try it out by opening a separate terminal and running `lorri daemon`
so that `direnv` can call out to it.
If you like it, you'll need to have it run when you log in,
but that's really out of scope for this guide.
(Hint: Home Manager has a dandy module for it.)

TMux will be ready to go as soon as it's installed.

## The Rest

All the other tools you'll need are in the `flake.nix` here,
so feel free to run through the remaining setup in [/README.md]
