extends RefCounted
## Base for test files. Methods named `test_*` run one by one; a failed check is recorded
## and the method goes on.

var failures: Array[String] = []
var current := ""


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s: %s" % [current, message])


func eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append(
			(
				"%s: %s\n    expected %s\n    got      %s"
				% [current, message, var_to_str(expected), var_to_str(actual)]
			)
		)


## An empty temp directory, removed by the runner.
func temp_dir(name: String) -> String:
	var dir := OS.get_cache_dir().path_join("anchorage-test-%s-%d" % [name, OS.get_process_id()])
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func remove(dir: String) -> void:
	OS.execute("rm", ["-rf", dir])


func repo_file(path: String) -> String:
	return FileAccess.get_file_as_string(
		ProjectSettings.globalize_path("res://").path_join("..").path_join(path)
	)
