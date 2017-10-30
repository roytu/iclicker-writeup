# Uploads an AVR binary to the given device
# Usage: ./upload.sh <file> <device ID>
avrdude -v -V -P $2 -c avrisp -p m8 -b 19200 -U flash:w:$1:r
