# Basic Tools

The development environment in this repo
is pretty opinionated.
Without too much effort it should be adaptable
to other approaches.

The motivation behind this
is that with your workstation set up this way,
you'll be able to
install the tools for individual software projects
just for them,
and make sure that you've got the right versions
of your toolchain installed as you switch between projects.
(Or even branches of the same project!)
All those requirements will be recorded
alongside the code that needs those tools,
and we save a ton of hassle working through a whole set up procedure.

This set up relies on a few basic tools,
to manage that description of requirements,
and to set them up automatically as you
switch to the project directory
or change branches.
Plus Tmux is an indespensible tool for managing complex workspaces.

If you don't have all of
`nix`, `direnv`, `tmux` and `lorri`
already installed on your workstation,
and you'd like to try them out,
here's a guide to doing that.

# Nix

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

You might also look at the `flake.nix` file in this repo:
that's the description of the tools needed,
and where to get them
for _this_ project.
You could set up a shell with those programs installed and available
by running `nix develop`
just to check it out.
It'll run as a sub-shell of your current one,
so when you're done messing around, you can `<Ctrl-D>`
to get out of it -
you'll notice that things like `cargo` and `elm`
aren't available anymore from the workspace.
(You might have them installed locally, though.)

# Global Requirements

Now we're going to add a few tools to your workstation.

`direnv` watches the directory your terminal is in and sets environment variables.
Since it can update your `PATH` it can also make sure that certain programs
are availabe on a per-directory basis,
which makes it incredibly powerful,
despite its simplicity.

`lorri` works with `direnv` to make sure that
software in your toolchain is installed based on the local `flake.nix` file.
With the right `direnv` configuration, it'll do the `nix develop` for you,
install everything in the background,
and then make the tools available on your `PATH` when they're ready.
One nice side effect is that it's easier to use your preferred shell this way.

Finally, `tmux` is a "terminal multiplexer" that lets you
create and manipulate sub-windows of your terminal,
so you can have multiple shells running next to each other.
This is incredibly handy when you want to have the manual up
and run a tool in another shell,
or edit in one shell,
and test the code you're editing in another.

Anyway, we're going to install all of those globally with

```shell
> nix profile install nixpkgs#direnv nixpkgs#lorri nixpkgs#tmux
```

# The Rest

All the other tools you'll need are in the `flake.nix` here,
so feel free to run through the remaining setup in [/README.md]
