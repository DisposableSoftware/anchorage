extends SceneTree
## Runs every tests/test_*.gd. Usage (from the repo root): scripts/test.sh
## A method named `xfail_*` is a reproduction of a known bug: it is listed but not run.
## `/implement` renames it to `test_*` when it fixes the bug.
## Tests run on the first frame, once `root` is in the tree, so they can add scenes to it.
## A script error inside a test is printed by Godot, not thrown, so scripts/test.sh also
## fails on "SCRIPT ERROR" in the output.


func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var failed := 0
	var passed := 0
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
		func(f: String): return f.begins_with("test_") and f.ends_with(".gd")
	)
	files.sort()
	for file in files:
		var script := load("res://tests/" + file) as GDScript
		if script == null:
			print("FAIL  %s does not load" % file)
			failed += 1
			continue
		for method in script.get_script_method_list():
			if method.name.begins_with("xfail_"):
				print(
					(
						"SKIP  %s::%s (known bug, see its Spec: trailer)"
						% [file.get_basename(), method.name]
					)
				)
				continue
			if not method.name.begins_with("test_"):
				continue
			var test: RefCounted = script.new()
			test.current = "%s::%s" % [file.get_basename(), method.name]
			test.call(method.name)
			if test.failures.is_empty():
				passed += 1
				print("PASS  %s" % test.current)
			else:
				failed += 1
				print("FAIL  %s" % test.current)
				for message in test.failures:
					print("  " + message)
	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
