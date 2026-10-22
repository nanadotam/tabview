#!/bin/zsh
# Regenerates docs/*.png and docs/demo.gif from made-up demo folders, entirely offscreen.
# Needs ImageMagick and ffmpeg (brew install imagemagick ffmpeg).
set -e
cd "$(dirname "$0")/.."
DEMO=$(mktemp -d)/demo
RAW=$(mktemp -d)
mkdir -p "$DEMO" docs

# --- Demo folders --------------------------------------------------------------
cd "$DEMO"
mkdir -p "1 Brand Assets" "2 Moodboard" "3 Photos" "4 Invoices" "5 Downloads" "6 Fonts" "7 Website" "8 Screenshots"
pal=('#F2C14E' '#F78154' '#4D9078' '#5B8CFF' '#B4436C' '#2E294E' '#E0D3DE' '#1B998B' '#FF9F1C' '#6C91C2')
for n in 1 2 3 4 5 6 7 8; do
  magick -size 640x480 "plasma:${pal[$((n%10+1))]}-${pal[$(((n+3)%10+1))]}" -blur 0x6 "3 Photos/IMG_00$n.jpg"
done
for n in 1 2 3 4 5 6; do
  magick -size 600x600 "gradient:${pal[$((n%10+1))]}-${pal[$(((n+5)%10+1))]}" -swirl $((n*60)) "2 Moodboard/ref-0$n.jpg"
done
magick -size 600x600 xc:'#5B8CFF' -fill white -font Helvetica-Bold -pointsize 220 -gravity center -annotate 0 'Tv' "1 Brand Assets/logo-primary.png"
magick -size 600x600 xc:'#111111' -fill '#5B8CFF' -font Helvetica-Bold -pointsize 220 -gravity center -annotate 0 'Tv' "1 Brand Assets/logo-dark.png"
for c in 5B8CFF F78154 F2C14E 1B998B; do magick -size 400x400 xc:"#$c" "1 Brand Assets/colour-$c.png"; done
printf '# Brand guidelines\n\nPrimary blue #5B8CFF.\n' > "1 Brand Assets/guidelines.md"
for n in 0412 0413 0414 0415 0416; do
  magick -size 595x842 xc:white -fill '#111' -font Helvetica-Bold -pointsize 48 -annotate +60+120 "INVOICE" \
    -font Helvetica -pointsize 22 -annotate +60+170 "No. $n" -fill '#ddd' \
    -draw 'rectangle 60,260 535,262' -draw 'rectangle 60,320 535,322' -draw 'rectangle 60,380 535,382' \
    -fill '#5B8CFF' -font Helvetica-Bold -pointsize 30 -annotate +60+480 "Total  \$1,${n:2}0.00" "4 Invoices/Invoice-$n.pdf"
done
for f in installer.dmg archive.zip podcast.mp3 slides.key; do touch "5 Downloads/$f"; done
magick -size 595x842 xc:'#F5F1EA' -fill '#222' -font Helvetica-Bold -pointsize 60 -annotate +50+150 "Report" "5 Downloads/report.pdf"
printf 'Remember to send the files.\n' > "5 Downloads/notes.txt"
for f in /System/Library/Fonts/Supplemental/{Georgia.ttf,Futura.ttc,Didot.ttc,Baskerville.ttc,Rockwell.ttc,Copperplate.ttc}; do
  [[ -f "$f" ]] && cp "$f" "6 Fonts/"
done
printf '<!doctype html><title>Home</title><h1>Hello</h1>' > "7 Website/index.html"
printf 'body{font-family:system-ui}\n' > "7 Website/styles.css"
printf 'console.log("hi")\n' > "7 Website/app.js"
printf '{"name":"site"}\n' > "7 Website/package.json"
printf '# Site\n' > "7 Website/README.md"
magick -size 800x500 xc:'#F7F7F7' -fill '#5B8CFF' -draw 'rectangle 0,0 800,60' "7 Website/hero.png"
for n in 1 2 3 4 5 6; do
  magick -size 800x500 xc:'#ECECEC' -fill "${pal[$n]}" -draw "roundrectangle 40,40 $((300+n*50)),$((200+n*30)) 20,20" \
    -fill '#ccc' -draw 'rectangle 40,420 760,440' "8 Screenshots/Screenshot 2026-10-2$n.png"
done
cd - >/dev/null

# --- Render offscreen ----------------------------------------------------------
swift build -c release
.build/release/Tabview --render-readme "$RAW" "$DEMO"

# --- Compose -------------------------------------------------------------------
# frame <in> <out> <bg-from> <bg-to>: soft shadow on a gradient backdrop.
frame() {
  local w=$(magick identify -format %w "$1") h=$(magick identify -format %h "$1")
  magick -size $((w+240))x$((h+240)) gradient:"$3-$4" \
    \( "$1" \( +clone -background black -shadow 28x30+0+18 \) +swap -background none -layers merge +repage \) \
    -gravity center -compose over -composite -resize 50% "$2"
}
frame "$RAW/grid-light.png"    docs/hero-light.png   '#DCE6FF' '#F6E7FF'
frame "$RAW/grid-dark.png"     docs/hero-dark.png    '#1B2350' '#3A1E4D'
frame "$RAW/preview-light.png" docs/preview.png      '#FFE9DA' '#FFF7E0'
magick "$RAW/settings-light.png" -resize 50% docs/settings-light.png
magick "$RAW/settings-dark.png"  -resize 50% docs/settings-dark.png

# Demo GIF: crossfade between storyboard frames.
FR=$(mktemp -d)
i=0
for f in "$RAW"/frame-*.png; do
  magick "$f" -resize 800x "$FR/$(printf %02d $i).png"; i=$((i+1))
done
ffmpeg -y -loglevel error -framerate 1.4 -i "$FR/%02d.png" \
  -vf "minterpolate=fps=12:mi_mode=blend,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=sierra2_4a" \
  -loop 0 docs/demo.gif
echo "docs/ updated"
