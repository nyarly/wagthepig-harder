#!/usr/bin/env bash

tmux new-window -dS -a 0 -c frontend -n FE-edit "nvim -S"
tmux new-window -dS -a 1 -c frontend -n FE
tmux new-window -dS -a 2 -n process-compose process-compose
tmux new-window -dS -a 3 -n top
tmux new-window -dS -a 4 -c backend -n BE
tmux new-window -dS -a 5 -c backend -n BE-edit "nvim -S"
