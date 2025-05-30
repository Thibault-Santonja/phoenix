.PHONY: to_webp

MAINTAINER = "Thibault Santonja"

to_webp:
	# find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec sh -c 'cwebp -quiet "$1" -o "${1%.*}.webp"' _ {} \;
	#
	# List all files with the following image extensions : PNG, JPG or JPEG
	# Resize all these images using `magick` : magick street.webp -resize 1080 street_1080.webp
	# Delete the parent image
	find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec sh -c 'magick "$1" -resize 1080 "${1%.*}.webp" && rm "$1"' _ {} \;
