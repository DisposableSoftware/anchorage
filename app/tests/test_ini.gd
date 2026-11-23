extends "res://tests/case.gd"

const Ini := preload("res://src/ini.gd")


func test_parses_sections_comments_and_unquoted_values() -> void:
	var parsed := Ini.parse(
		"# c\n; c\n[window]\nwidth = 1500\n[view]\ngreeting=Hi there\nbad line\n"
	)
	eq(parsed["window"]["width"], "1500", "spaces around =")
	eq(parsed["view"]["greeting"], "Hi there", "value keeps inner spaces")
	eq(parsed.size(), 2, "only the two sections")


func test_lists() -> void:
	eq(Ini.split_list("Ctrl+Q; Alt+F4;;"), PackedStringArray(["Ctrl+Q", "Alt+F4"]), "split on ;")
	eq(Ini.split_list("").size(), 0, "empty value is an empty list")
