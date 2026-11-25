extends SceneTree
## The swap of a self-update (UPD-6, UPD-7) on real files, for scripts/manual/steam-install.sh:
##   godot --headless --path app -s res://tests/self_update_swap.gd -- RECORD APPIMAGE NEW
## puts NEW beside APPIMAGE as `.new` and runs self_update.gd's swap, which renames it over
## APPIMAGE, keeps `.previous` and updates the installer's RECORD. Exits 1 on an error.

const SelfUpdate := preload("res://src/self_update.gd")


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 3:
		printerr("usage: -- RECORD APPIMAGE NEW")
		quit(2)
		return
	var fresh := SelfUpdate.new_path(args[1])
	var err := DirAccess.copy_absolute(args[2], fresh)
	var error := error_string(err) if err != OK else ""
	if error.is_empty():
		# What `verify` does to a download before the swap.
		FileAccess.set_unix_permissions(fresh, SelfUpdate.MODE)
		error = SelfUpdate.swap(args[1], args[0], FileAccess.get_sha256(fresh))
	if not error.is_empty():
		printerr(error)
	quit(0 if error.is_empty() else 1)
