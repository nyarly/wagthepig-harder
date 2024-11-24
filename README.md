# Wag The Pig, Harder!

An update of the WagThePig web app to use Axum(Rust) and Elm.

In part, we hope this will lead to more development activity,
since we won't have to chase Rails versions.

# Development

To get started, you should just need to run `process-compose`,
which will set up all the support services for developing the app.
We take an agnostic view of workstation setup,
which means you're on you own for making sure that `process-compose`
and the rest of your toolchain are installed.

That said,
there's been a fair amount of effort made to simplify things,
if you're willing to crib from `nyarly`'s setup.

I'd highly recommend,
as foundational tools,
`nix`, `direnv`, `tmux` and `lorri`.
Installing those are a little out of scope,
(but see [/devsupport/wwnd.md])
but if you're already using some or all of those tools,
this setup will be a breeze.

Copy `envrc.example` into your `.envrc` for this repo,
start `tmux`,
and run `devsupport/setup_tmux.sh`
and you should have a solid development environment ready to go.

## Go your own way

If you have your own opinions and preferences
about how to develop software
that are somehow different from `nyarly`'s,
here's where to find the information you'll need to adapt
the preferred setup here to your own.

First, you'll find `devsupport/setup_tmux.sh`
is set up to create Neovim editors using `direnv`,
but you can tailor it as you see fit in a git-ignored local copy.

`direnv` is a really handy tool
that establishes environment variables
based on the directory a shell is running in.
There are alternatives,
and if you have one you prefer,
feel free to translate the `envrc.example`.

If you prefer not to use `lorri`,
you can adapt the `envrc` (or your preferred configuration)
to use `nix develop`,
or whatever your local preference is.
Under `direnv`, `use flake` should work.

Finally,
if you don't use Nix, and prefer not to,
there's a `flake.nix` with the project toolchain set up.
At the very least,
if you want to do everything for yourself
that can serve as a shopping list -
just make sure you have everything from the `buildInputs` in that file installed
and you should be good.
