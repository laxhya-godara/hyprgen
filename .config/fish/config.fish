if status is-interactive
    set fish_greeting # Commands to run in interactive sessions can go here
end


function fish_greeting
    ~/.config/fish/torii-greeting.sh
end
starship init fish | source

fish_add_path ~/.local/bin

alias s='sudo pacman -Ss'
alias i='sudo pacman -S'
alias r='sudo pacman -Rns'
alias ii='aur-fetch-installer.sh -c'
alias scan='aur-fetch-installer.sh -l'
alias hyprconf='code .config/hypr/hyprland.lua'
alias gd='gallery-dl'
alias yd='ytdlp'


fish_add_path /home/laxhya/.spicetify
