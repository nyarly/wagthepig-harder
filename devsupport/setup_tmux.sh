#!/usr/bin/env bash

# TODO runnable in or out of Tmux
# conditionally create `new-session`
# but put all the windows in the appropriate place
#
set -x

topdir=$(realpath $(dirname ${0})/..)

tmux new-window -S -c $topdir/frontend -n FE-edit "direnv exec . nvim -S"
tmux new-window -S -c $topdir/frontend -n FE
tmux new-window -S -c $topdir -n process-compose "direnv exec . process-compose"
tmux new-window -S -c $topdir -n top
tmux new-window -S -c $topdir/backend -n BE
tmux new-window -S -c $topdir/backend -n BE-edit "direnv exec . nvim -S"

tmux swap-window -t :0 -s =FE-edit
tmux swap-window -t :1 -s =FE
tmux swap-window -t :2 -s =process-compose
tmux swap-window -t :3 -s =top
tmux swap-window -t :4 -s =BE
tmux swap-window -t :5 -s =BE-edit

for n in FE-edit FE process-compose top BE BE-edit; do
  tmux set-option -t "=:$n" remain-on-exit on
done
