# Wag The Pig, Harder!

An update of the WagThePig web app to use Axum(Rust) and Elm.

In part, we hope this will lead to more development activity,
since we won't have to chase Rails versions.

# Development

There's been some thought and effort
put into building a reusable and reproducable
development environment.
This has been driven by `nyarly`'s preferences,
and while we're confident you'll enjoy it,
we're also pointedly aware of the frustration
of a forced development approach.
Therefore, two approaches are presented here:
`nyarly`'s way (which we'll do our utmost to support)
and your own way.

## nyarly's way

There are a few
foundational tools:
`nix`, `direnv`, `tmux` and `lorri`.
Installing those are a little out of scope,
(but see [/devsupport/wwnd.md])
but if you're already using some or all of those tools,
this setup will be a breeze.

1. Copy `envrc.example` into your `.envrc` for this repo,
which will get Lorri to set up the `devShell` in the `flake.nix`.
0. From there, start `tmux`
0. Run `devsupport/setup_tmux.sh`
which will kick off development services
and start windows for Neovim editors for frontend and backend.
0. Happy hacking!

## Go your own way

If you have your own opinions and preferences
about how to develop software
that are somehow different from `nyarly`'s,
here's where to find the information you'll need to adapt
the preferred setup here to your own.

First, you'll find `devsupport/setup_tmux.sh`
is set up to create Neovim editors using `direnv`,
but you can tailor it as you see fit in a git-ignored local copy.

Note that the development servers
are run (from `setup_tmux.sh`) under `process-compose`,
which sets up all the support services for developing the app.
The specific commands are described in its `process-compose.yaml`.

`direnv` is a really handy tool
that establishes environment variables
based on the directory a shell is running in.
There are alternatives,
and if you have one you prefer,
feel free to translate the `envrc.example`.
You can also skip `direnv` and `lorri` by just running `nix develop`
and working in the resulting subshell.

If you prefer not to use `lorri`,
you can adapt the `envrc` (or your preferred configuration)
to use `nix develop`,
or whatever your local preference is.
Under `direnv`, `use flake` should work.

Finally,
if you don't use Nix, and prefer not to,
the project toolchain set up
is described in `flake.nix`.
At the very least,
that can serve as a shopping list -
if you want to do everything for yourself
look for `pkgs.mkShell` in that file,
and make sure you have everything from the `buildInputs` installed
and you should be good.

It's out of the scope of this guide,
unfortunately to provide precise package listings
for various distributions.
If you assemble your own list,
we'd very much welcome a PR with it for future use!
