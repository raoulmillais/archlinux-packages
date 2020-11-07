main() {
	check_root
	ensure_deps
	mkarchiso -v ./archiso-profile
}

check_root() {
	[ "$(id -u)" -ne 0 ] && echo "$0 must be run as root" && exit
}


ensure_deps() {
	echo "Checking dependencies"

	if ! pacman -Qi archiso >/dev/null 2>&1 || ! pacman -Qi mkinitcpio-archiso >/dev/null 2>&1; then
		echo "archiso and or mkinitcpio-archiso are not installed, installing"
		pacman -Sy --noconfirm archiso mkinitcpio-archiso
	fi
}

main "$@"

