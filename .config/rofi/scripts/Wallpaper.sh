#!/bin/bash

WALL_DIR="$HOME/Pictures"
CACHE_DIR="$HOME/.cache/rofi-wallpapers"

mkdir -p "$CACHE_DIR"

if ! pidof awww-daemon >/dev/null; then
    awww-daemon &
    sleep 0.5
fi

read -r -d '' GRID_THEME << 'EOF'
@import "/home/laxhya/.config/rofi/colors.rasi"

* { font: "JetBrains Mono 14"; }

window {
    transparency:                "real";
    location:                    center;
    anchor:                      center;
    fullscreen:                  false;
    width:                       80%;
    x-offset:                    0px;
    y-offset:                    0px;
    enabled:                     true;
    margin:                      0px;
    padding:                     0px;
    border:                      2px;
    border-radius:               0px;
    border-color:                @primary-fixed;
    background-color:            transparent;
    cursor:                      "default";
}

mainbox {
    enabled:                     true;
    spacing:                     20px;
    margin:                      0px;
    padding:                     50px;
    border:                      0px;
    border-radius:               0px;
    border-color:                transparent;
    background-color:            transparent;
    children:                    [ "inputbar", "listview" ];
}

inputbar { enabled: false; }

entry {
    enabled:                     true;
    expand:                      false;
    width:                       350px;
    padding:                     15px 20px;
    border-radius:               15px;
    background-color:            transparent;
    text-color:                  transparent;
    cursor:                      text;
    placeholder:                 "Search...";
    placeholder-color:           inherit;
}

listview {
    enabled:                     true;
    columns:                     4;
    lines:                       1;         
    cycle:                       true;
    dynamic:                     true;
    scrollbar:                   false;
    layout:                      vertical;  
    reverse:                     false;
    fixed-height:                true;
    fixed-columns:               true;
    spacing:                     20px;
    margin:                      0px;
    padding:                     0px;
    border:                      0px;
    border-radius:               0px;
    border-color:                transparent;
    background-color:            transparent;
    text-color:                  transparent;
    cursor:                      "default";
}

element {
    enabled:                     true;
    spacing:                     20px;
    margin:                      0px;
    padding:                     50px 10px 10px 10px;
    border:                      2px solid;
    border-radius:               10px;
    border-color:                transparent;
    background-color:            transparent;
    text-color:                  transparent;
    orientation:                 vertical;
    cursor:                      pointer;
}

element normal.normal, element alternate.normal {
    background-color:            transparent;
    text-color:                  transparent;
}

element selected.normal {
    border-color:                @primary-fixed;
    background-color:            transparent;
    text-color:                  transparent;
}

element-icon {
    padding:                     0px;
    background-color:            transparent;
    text-color:                  inherit;
    size:                        340px;
}
EOF


shopt -s extglob nocaseglob nullglob

SELECTED=$(
for img in "$WALL_DIR"/*.@(jpg|jpeg|png|webp); do
    
    filename="${img##*/}"
    thumb="$CACHE_DIR/$filename"

    if [[ ! -f "$thumb" ]]; then
        magick "$img" -thumbnail 400x400^ -gravity center -extent 400x400 "$thumb"
    fi

    printf "%s\0icon\x1f%s\n" "$filename" "$thumb"
done | rofi \
-dmenu \
-i \
-show-icons \
-theme-str "$GRID_THEME" \
-p "" \
-name "wallpaper-picker"
)

if [ -n "$SELECTED" ]; then
    TARGET_IMG="$WALL_DIR/$SELECTED"

    awww img "$TARGET_IMG" \
        --transition-type random \
        --transition-fps 60 \
        --transition-duration 2.5 \
        --transition-pos "top-right"

    matugen image "$TARGET_IMG" --source-color-index 0
    /home/laxhya/.config/matugen/post-hook-scripts/xdg.sh &
    notify-send "NEW COLORS ARE HERE!"
fi