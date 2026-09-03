#!/usr/bin/env bash
R=$'\e[38;2;224;86;59m'
RH=$'\e[38;2;239;106;79m'
D=$'\e[38;2;51;55;63m'
K=$'\e[38;2;63;69;80m'
S=$'\e[38;2;139;145;156m'
T=$'\e[38;2;196;204;218m'
DIM=$'\e[38;2;91;102;120m'
G=$'\e[38;2;91;191;115m'
X=$'\e[0m'

clock=$(date +%H:%M)
day=$(LC_TIME=C date "+%A · %-d %b")

up=$(awk '{print int($1)}' /proc/uptime)
ud=$((up/86400)); uh=$(((up%86400)/3600)); um=$(((up%3600)/60))
if [ "$ud" -gt 0 ]; then upt="${ud}d ${uh}h"; else upt="${uh}h ${um}m"; fi

read -ra a < /proc/stat
sleep 0.08
read -ra b < /proc/stat
t1=0; for v in "${a[@]:1}"; do t1=$((t1+v)); done
t2=0; for v in "${b[@]:1}"; do t2=$((t2+v)); done
id1=$((a[4]+a[5])); id2=$((b[4]+b[5]))
dt=$((t2-t1)); di=$((id2-id1))
cpu=$(( dt>0 ? 100*(dt-di)/dt : 0 ))

# --- CPU temp: AMD (k10temp) or Intel (coretemp) ---
ctemp="--"
for hw in /sys/class/hwmon/*; do
name=$(cat "$hw/name" 2>/dev/null)
if [ "$name" = "k10temp" ]; then
for lbl in "$hw"/temp*_label; do
            [ "$(cat "$lbl" 2>/dev/null)" = "Tctl" ] && ctemp=$(( $(cat "${lbl%_label}_input") / 1000 ))
done
        [ "$ctemp" = "--" ] && [ -r "$hw/temp1_input" ] && ctemp=$(( $(cat "$hw/temp1_input") / 1000 ))
break
elif [ "$name" = "coretemp" ]; then
for lbl in "$hw"/temp*_label; do
case "$(cat "$lbl" 2>/dev/null)" in
"Package id"*) ctemp=$(( $(cat "${lbl%_label}_input") / 1000 )); break ;;
esac
done
        [ "$ctemp" = "--" ] && [ -r "$hw/temp1_input" ] && ctemp=$(( $(cat "$hw/temp1_input") / 1000 ))
break
fi
done

# --- GPU: Nvidia (nvidia-smi) or Intel integrated (i915 sysfs freq scaling) ---
gpu="--"; gtemp="--"
if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
g=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
gpu=$(echo "$g" | awk -F, '{gsub(/ /,"");print $1}')
gtemp=$(echo "$g" | awk -F, '{gsub(/ /,"");print $2}')
else
for card in /sys/class/drm/card*; do
cname=$(basename "$card")
        [[ "$cname" =~ ^card[0-9]+$ ]] || continue
        [ "$(cat "$card/device/vendor" 2>/dev/null)" = "0x8086" ] || continue
gmax=$(cat "$card/gt_max_freq_mhz" 2>/dev/null)
gmin=$(cat "$card/gt_min_freq_mhz" 2>/dev/null)
gcur=$(cat "$card/gt_cur_freq_mhz" 2>/dev/null)
if [ -n "$gmax" ] && [ -n "$gmin" ] && [ -n "$gcur" ] && [ "$gmax" -gt "$gmin" ]; then
gpu=$(( 100*(gcur-gmin)/(gmax-gmin) ))
(( gpu < 0 )) && gpu=0
(( gpu > 100 )) && gpu=100
fi
        gtemp="$ctemp"   # Iris Xe is on-die; no separate sensor, mirrors package temp
break
done
fi

mt=$(awk '/MemTotal/{print $2}' /proc/meminfo)
ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
mu=$((mt-ma))
rused=$(awk "BEGIN{printf \"%.1f\",$mu/1048576}")
rtot=$(awk "BEGIN{printf \"%.0f\",$mt/1048576}")
rpct=$((100*mu/mt))

read -r dpct davail < <(df -BG --output=pcent,avail / 2>/dev/null | tail -1)
dpct=${dpct// /}; davail=${davail// /}; davail=${davail%G}

i3="${R}${clock}${X}"
i4="${DIM}${day} · up ${upt}${X}"
i6="${DIM}cpu  ${G}${cpu}%${DIM} · ${ctemp}°C${X}"
i7="${DIM}gpu  ${G}${gpu}%${DIM} · ${gtemp}°C${X}"
i8="${DIM}ram  ${T}${rused} ${DIM}/ ${rtot} GB · ${T}${rpct}%${X}"
i9="${DIM}disk ${T}${dpct} ${DIM}· ${davail} GB free${X}"

# Store lines into an array
lines=(
"${K}      ╱▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔╲${X}"
"${K}   ▗▄████████████████████▄▖${X}"
"${D}      ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${X}        ${i3}"
"${R}        ███   ${D}▐▌${R}   ███${X}          ${i4}"
"${R}    ▄▄▄▄███▄▄▄▄▄▄▄▄███▄▄▄▄${X}"
"${RH}    ▀▀▀▀███▀▀▀▀▀▀▀▀███▀▀▀▀${X}      ${i6}"
"${R}        ███        ███${X}          ${i7}"
"${R}        ███        ███${X}          ${i8}"
"${R}        ███        ███${X}          ${i9}"
"${R}        ███        ███${X}"
"${S}       ▟███▙      ▟███▙${X}"
)

# Detect terminal width
cols=$(tput cols 2>/dev/null || echo "${COLUMNS:-80}")

# Find longest visual width (stripping ANSI escapes)
max_len=0
for line in "${lines[@]}"; do
clean=$(printf '%s' "$line" | sed -r "s/\x1B\[[0-9;]*[a-zA-Z]//g")
len=${#clean}
    (( len > max_len )) && max_len=$len
done

# Calculate left margin
pad=$(( (cols - max_len) / 2 ))
(( pad < 0 )) && pad=0
padding=$(printf '%*s' "$pad" '')

# Print output
echo
for line in "${lines[@]}"; do
printf '%s%s\n' "$padding" "$line"
done
echo#!/usr/bin/env bash
R=$'\e[38;2;224;86;59m'
RH=$'\e[38;2;239;106;79m'
D=$'\e[38;2;51;55;63m'
K=$'\e[38;2;63;69;80m'
S=$'\e[38;2;139;145;156m'
T=$'\e[38;2;196;204;218m'
DIM=$'\e[38;2;91;102;120m'
G=$'\e[38;2;91;191;115m'
X=$'\e[0m'

clock=$(date +%H:%M)
day=$(LC_TIME=C date "+%A · %-d %b")

up=$(awk '{print int($1)}' /proc/uptime)
ud=$((up/86400)); uh=$(((up%86400)/3600)); um=$(((up%3600)/60))
if [ "$ud" -gt 0 ]; then upt="${ud}d ${uh}h"; else upt="${uh}h ${um}m"; fi

read -ra a < /proc/stat
sleep 0.08
read -ra b < /proc/stat
t1=0; for v in "${a[@]:1}"; do t1=$((t1+v)); done
t2=0; for v in "${b[@]:1}"; do t2=$((t2+v)); done
id1=$((a[4]+a[5])); id2=$((b[4]+b[5]))
dt=$((t2-t1)); di=$((id2-id1))
cpu=$(( dt>0 ? 100*(dt-di)/dt : 0 ))

ctemp="--"
for hw in /sys/class/hwmon/*; do
    if [ "$(cat "$hw/name" 2>/dev/null)" = "k10temp" ]; then
        for lbl in "$hw"/temp*_label; do
            [ "$(cat "$lbl" 2>/dev/null)" = "Tctl" ] && ctemp=$(( $(cat "${lbl%_label}_input") / 1000 ))
        done
        [ "$ctemp" = "--" ] && [ -r "$hw/temp1_input" ] && ctemp=$(( $(cat "$hw/temp1_input") / 1000 ))
        break
    fi
done

gpu="--"; gtemp="--"
if command -v nvidia-smi >/dev/null 2>&1; then
    g=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | head -1)
    gpu=$(echo "$g" | awk -F, '{gsub(/ /,"");print $1}')
    gtemp=$(echo "$g" | awk -F, '{gsub(/ /,"");print $2}')
fi

mt=$(awk '/MemTotal/{print $2}' /proc/meminfo)
ma=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
mu=$((mt-ma))
rused=$(awk "BEGIN{printf \"%.1f\",$mu/1048576}")
rtot=$(awk "BEGIN{printf \"%.0f\",$mt/1048576}")
rpct=$((100*mu/mt))

read -r dpct davail < <(df -BG --output=pcent,avail / 2>/dev/null | tail -1)
dpct=${dpct// /}; davail=${davail// /}; davail=${davail%G}

i3="${R}${clock}${X}"
i4="${DIM}${day} · up ${upt}${X}"
i6="${DIM}cpu  ${G}${cpu}%${DIM} · ${ctemp}°C${X}"
i7="${DIM}gpu  ${G}${gpu}%${DIM} · ${gtemp}°C${X}"
i8="${DIM}ram  ${T}${rused} ${DIM}/ ${rtot} GB · ${T}${rpct}%${X}"
i9="${DIM}disk ${T}${dpct} ${DIM}· ${davail} GB free${X}"

echo
printf '%s\n' "${K}      ╱▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔▔╲${X}"
printf '%s\n' "${K}   ▗▄████████████████████▄▖${X}"
printf '%s\n' "${D}      ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀${X}        ${i3}"
printf '%s\n' "${R}        ███   ${D}▐▌${R}   ███${X}          ${i4}"
printf '%s\n' "${R}    ▄▄▄▄███▄▄▄▄▄▄▄▄███▄▄▄▄${X}"
printf '%s\n' "${RH}    ▀▀▀▀███▀▀▀▀▀▀▀▀███▀▀▀▀${X}      ${i6}"
printf '%s\n' "${R}        ███        ███${X}          ${i7}"
printf '%s\n' "${R}        ███        ███${X}          ${i8}"
printf '%s\n' "${R}        ███        ███${X}          ${i9}"
printf '%s\n' "${R}        ███        ███${X}"
printf '%s\n' "${S}       ▟███▙      ▟███▙${X}"
echo
