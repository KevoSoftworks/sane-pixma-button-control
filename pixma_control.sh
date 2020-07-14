#!/bin/bash

# The amount of time to wait before checking a button press.
POLLING_TIMEOUT=3

# Ensure that these directories exist, and that the user running the script
# has write access to these directories.
OUTPUT_DIR=/srv/samba/_scans_

# Get the device name of the scanner
#
# Input: None
# Output: Scanimage device identifier
get_device_name () {
	# According to the sane-pixma man page, the device name is always formatted
	# as `pixma:XXXXYYYY_ZZZZZ`.
	scanimage -L | sed "s/.*\(pixma:[A-Z0-9_]*\).*/\1/"
}

# Poll which button was pressed on the scanner
#
# Input: device identifier
# Output: target status
#
# Note: If multiple buttons have been pressed between two polls, the first poll
# will return the first button pressed. A second poll will return the last
# button that was pressed. All other button presses will be lost.
poll_target () {
	# According to the sane-pixma man page, the status of the buttons can be
	# read from the list of options using `scanimage -A`. There doesn't seem to
	# a better way of doing this.
	# Furthermore, we pipe stderr to stdout to prevent the "Output format is
	# not set" message.
	scanimage --device-name="$1" -A 2>&1 | grep "target" \
		| sed "s/.*\[\([0-9]\)\].*/\1/"
}

# Create a temporary directory to hold scans
#
# Input: None
# Output: Directory path
create_tmp_dir () {
	mktemp -d -t pixma-scan-XXXXXXXX
}

# Remove the temporary directory (and its contents)
#
# Input: Temporary directory path
# Output: None
remove_tmp_dir () {
	rm -rf "$1"
}

# Create a temporary filename for scans
#
# Input: Temporary directory path, extension
# Output: Incremental filename
create_filename () {
	echo scan-$(ls "$1"/scan-* 2>/dev/null | wc -l)."$2"
}

# Create a scan
#
# Input: Device name, output path, resolution
# Output: None
scan_image () {
	scanimage \
		--device-name="$1" \
		--format="png" \
		--resolution="$3" \
		--output-file="$2"
}

# Core loop
# Obtain the device name
device=$(get_device_name)
echo "Using scanning device $device"

# Poll the button status every POLLING_TIMEOUT seconds
while [[ -n "${device}" ]]; do
	action=$(poll_target $device)
	if [[ $action -ne 0 ]]; then
		echo "Scan request received. Action $action."
	
		# Setup the scanning parameters
		if [[ -z "${tmp_dir}" ]]; then
			tmp_dir=$(create_tmp_dir)
			resolution=300

			echo "Temporary directory at $tmp_dir."
		fi

		# Start scanning
		output_path="$tmp_dir/$(create_filename $tmp_dir png)"
		echo "Scanning $output_path"
		scan_image $device $output_path $resolution

		# If we are making a copy, send it to the printer
		if [[ $action -eq 1 ]]; then
			echo "Printing $output_path"
			lp "$output_path"
		fi

		# Save files if we are not creating a batch PDF
		if [[ $action -ne 4 ]]; then
			# If we hit the send button, we want to convert to PDF and move it
			if [[ $action -eq 3 ]]; then
				echo "Converting scans to PDF and moving."
				convert "$tmp_dir/*.png" -compress jpeg \
					-quality 75 "$tmp_dir/out.pdf"
				mv "$tmp_dir/out.pdf" \
					"$OUTPUT_DIR/scan-$(date +'%F-%H-%M-%S').pdf"
			# Otherwise, we just want to move the scan
			else
				echo "Moving scan."
				mv $output_path \
					"$OUTPUT_DIR/scan-$(date +'%F-%H-%M-%S').png"
			fi

			# Delete the temporary directory
			echo "Cleaning up."
			remove_tmp_dir $tmp_dir
			unset tmp_dir
		fi
		echo "Ready."
	fi

	sleep $POLLING_TIMEOUT
done
