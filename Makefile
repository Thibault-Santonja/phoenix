.PHONY: to_webp

MAINTAINER = "Thibault Santonja"

to_webp:
	find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec sh -c 'cwebp -quiet "$1" -o "${1%.*}.webp"' _ {} \;
	# to resize images : magick convert street.webp -resize 1080 street_1080.webp
