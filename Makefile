.PHONY: convert_to_webp convert_to_progressive_jpg

MAINTAINER = "Thibault Santonja"

convert_to_webp:
	# **Advantages of WEBP**
	# Lightweight format, so faster loading of the whole image
	#
	# **Disadvantages of WEBP**
	# Requires the whole image to be loaded to display it OR scanning effect when the image is loaded
	#
	# List all files with the following image extensions : PNG, JPG or JPEG
	# Resize all these images using `magick` : magick street.webp -resize 2160 street_2160.webp
	find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec sh -c 'magick "$1" -resize 2160 "${1%.*}.webp"' _ {} \;

convert_to_progressive_jpg:
	# **Advantages of progressive JPG**
	# Loads a first image version really quickly (in a low-resolution version)
	#
	# **Disadvantages of progressive JPG**
	# Requires CPU resources to compress and decompress the image (~2.5 times more than WEBP)
	#
	# List all files with the following image extensions : PNG, JPG or JPEG
	# Convert to progressive using `magick` : magick street.jpg -resize 2160 -strip -interlace Plane street.jpg
	find . -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) -exec sh -c 'magick "$1" -strip -interlace Plane -resize 2160 "${1%.*}.jpg"' _ {} \;
