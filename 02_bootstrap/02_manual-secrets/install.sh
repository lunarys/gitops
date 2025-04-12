SCRIPT_DIR="$(dirname "$0")"

if [ -z "$1" ]; then
	files="$SCRIPT_DIR/"*.yaml
else
	files="$1"
fi

for file in $files; do
	echo "Processing yaml file: $file"
	manifest="$(yq "$file")"

	for key in $(echo "$manifest" | yq ".stringData | keys[]"); do
		value="$(echo "$manifest" | yq ".stringData.$key")"

		if [ -z "$value" ]; then
			echo "Enter value for '$key':"
		else
			echo "Enter value for '$key' (default='$value'):"
		fi

		read newValue
		#if [ -z "$newValue" ]; then
		#	echo no value
		#else
		#	echo value $newValue
		#fi

		if [ -n "$newValue" ]; then
			manifest="$(echo "$manifest" | NEW_VALUE="$newValue" yq ".stringData.$key = strenv(NEW_VALUE)")"
		fi
	done

	echo "New manifest:"
	echo "---"
	echo "$manifest" | yq
	echo "---"

	echo "Apply manifest? (Y/n)"
	read confirmation
	if [ -z "$confirmation" ] || [ "$confirmation" == "y" ]; then
		echo "Applying manifest for $file..."
		echo "$manifest" | kubectl apply -f -
	else
		echo "WARN: Not applying manifest for $file"
	fi
done
