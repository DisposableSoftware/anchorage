extends "res://tests/case.gd"

const Releases := preload("res://src/releases.gd")
const State := preload("res://src/state.gd")
const FakeHttp := preload("res://tests/fake_http.gd")

const BASE := "https://github.com/HarbourMasters/Starship/releases/download/v2.0.0/"


func _port(suffix := "-linux.zip") -> Dictionary:
	return {"id": "starship", "repo": "HarbourMasters/Starship", "asset_suffix": suffix}


func _release_json(assets: Array, extra := {}) -> Dictionary:
	var out := {"tag_name": "v2.0.0", "published_at": "2025-05-25T00:00:00Z", "assets": assets}
	out.merge(extra, true)
	return out


func _asset(name: String, size := 80, url := "") -> Dictionary:
	return {
		"name": name,
		"size": size,
		"browser_download_url": url if not url.is_empty() else BASE + name,
	}


func test_picks_the_asset_by_suffix_and_ignores_the_others() -> void:
	var data := _release_json(
		[
			_asset("Starship-Barnard-Alfa-Switch.zip"),
			_asset("Starship-Barnard-Alfa-Windows.zip"),
			_asset("Starship-Barnard-Alfa-Linux.zip", 79980135),
		]
	)
	var parsed := Releases.parse_latest(_port(), data)
	check(parsed["ok"], "found")
	eq(parsed["release"]["tag"], "v2.0.0", "tag")
	eq(parsed["release"]["asset"]["name"], "Starship-Barnard-Alfa-Linux.zip", "asset")
	eq(parsed["release"]["asset"]["size"], 79980135, "size is an int")
	eq(parsed["release"]["asset"]["url"], BASE + "Starship-Barnard-Alfa-Linux.zip", "url")


func test_suffix_for_a_bare_appimage_and_a_fixed_name() -> void:
	var soh := {"id": "soh", "repo": "HarbourMasters/Shipwright", "asset_suffix": ".appimage"}
	var url := (
		"https://github.com/HarbourMasters/Shipwright/releases/download/9.3.1/"
		+ "SoH-Dewey-Bravo.appimage"
	)
	var data := {
		"tag_name": "9.3.1",
		"assets":
		[
			_asset("SoH-Dewey-Bravo-Mac.zip", 5, url + ".zip"),
			_asset("SoH-Dewey-Bravo.appimage", 9, url)
		],
	}
	eq(
		Releases.parse_latest(soh, data)["release"]["asset"]["name"],
		"SoH-Dewey-Bravo.appimage",
		"AppImage"
	)
	var kart := {
		"id": "k", "repo": "HarbourMasters/Starship", "asset_suffix": "spaghetti-linux.zip"
	}
	check(
		Releases.parse_latest(kart, _release_json([_asset("spaghetti-linux.zip")]))["ok"],
		"fixed name"
	)


func test_no_matching_asset_is_an_error_with_the_tag() -> void:
	var parsed := Releases.parse_latest(_port(), _release_json([_asset("x-Windows.zip")]))
	check(not parsed["ok"], "no match")
	check("v2.0.0" in parsed["error"], "names the release")


func test_prereleases_drafts_and_odd_answers_are_not_releases() -> void:
	var assets := [_asset("x-Linux.zip")]
	check(
		not Releases.parse_latest(_port(), _release_json(assets, {"prerelease": true}))["ok"], "pre"
	)
	check(not Releases.parse_latest(_port(), _release_json(assets, {"draft": true}))["ok"], "draft")
	check(not Releases.parse_latest(_port(), {"message": "Not Found"})["ok"], "error object")
	check(not Releases.parse_latest(_port(), null)["ok"], "null")
	check(
		not Releases.parse_latest(_port(), _release_json([_asset("x-Linux.zip", 0)]))["ok"], "empty"
	)


func test_foreign_urls_and_hosts_are_refused() -> void:
	var port := _port()
	check(Releases.url_allowed(port, BASE + "a-Linux.zip"), "own release asset")
	check(
		not Releases.url_allowed(
			port, "https://evil.example/HarbourMasters/Starship/releases/download/v/a"
		),
		"host"
	)
	check(
		not Releases.url_allowed(
			port, "http://github.com/HarbourMasters/Starship/releases/download/v/a"
		),
		"http"
	)
	check(
		not Releases.url_allowed(port, "https://github.com/Other/Starship/releases/download/v/a"),
		"other repo"
	)
	check(
		not Releases.url_allowed(port, "https://github.com/HarbourMasters/Starship/archive/v.zip"),
		"not a release asset"
	)
	check(not Releases.url_allowed(port, BASE + "../../../x"), "dot dot")
	check(
		not Releases.url_allowed(
			port, "https://github.com@evil.example/HarbourMasters/Starship/releases/download/v/a"
		),
		"userinfo"
	)
	var hostile := _release_json([_asset("a-Linux.zip", 5, "https://evil.example/a-Linux.zip")])
	check(not Releases.parse_latest(port, hostile)["ok"], "release with a foreign asset URL")


func test_redirects_stay_on_github() -> void:
	check(Releases.redirect_allowed("https://objects.githubusercontent.com/x?y=1"), "cdn")
	check(Releases.redirect_allowed("https://release-assets.githubusercontent.com/x"), "cdn 2")
	check(Releases.redirect_allowed("https://github.com/x"), "github")
	check(not Releases.redirect_allowed("http://github.com/x"), "plain http")
	check(not Releases.redirect_allowed("https://evilgithub.com/x"), "lookalike")
	check(not Releases.redirect_allowed("https://github.com.evil.example/x"), "suffix trick")
	check(not Releases.redirect_allowed("https://github.com:444@evil.example/x"), "userinfo")
	check(not Releases.redirect_allowed(""), "empty")


func test_update_available_is_a_difference_of_tags() -> void:
	check(Releases.update_available("9.3.0", "9.3.1"), "differs")
	check(not Releases.update_available("9.3.1", "9.3.1"), "same")
	check(not Releases.update_available("", "9.3.1"), "not installed")
	check(not Releases.update_available("9.3.1", ""), "latest unknown")
	check(Releases.update_available("9.4.0", "9.3.1"), "any difference counts")


func test_once_per_hour_rule_with_a_clock() -> void:
	var now := 1_000_000
	check(Releases.check_due(0, now, true), "never checked")
	check(not Releases.check_due(now - 3599, now, true), "59 minutes ago")
	check(Releases.check_due(now - 3600, now, true), "an hour ago")
	check(not Releases.check_due(now - 7200, now, false), "check_updates = false")
	check(Releases.check_due(now - 10, now, false, true), "refresh always checks")
	check(Releases.check_due(now + 500, now, true), "last check in the future")


func test_fetch_latest_reads_the_catalog_repo() -> void:
	var http := FakeHttp.new()
	var port := _port()
	http.json["https://api.github.com/repos/HarbourMasters/Starship/releases/latest"] = _release_json(
		[_asset("S-Linux.zip")]
	)
	var got := []
	Releases.fetch_latest(http, port, func(r: Dictionary) -> void: got.append(r))
	check(got[0]["ok"], "ok")
	check(not got[0]["offline"], "online")
	eq(http.requests.size(), 1, "one request")


func test_a_failed_check_is_offline_and_keeps_the_state() -> void:
	var dir := temp_dir("rel_offline")
	var state := State.load_from(dir.path_join("state.ini"))
	state.set_latest("starship", "v1.0.0")
	var http := FakeHttp.new()
	http.offline = true
	var got := []
	Releases.check(http, state, _port(), func(r: Dictionary) -> void: got.append(r))
	check(not got[0]["ok"], "failed")
	check(got[0]["offline"], "offline")
	eq(state.latest_version("starship"), "v1.0.0", "last known tag stays")
	http.offline = false
	http.status["https://api.github.com/repos/HarbourMasters/Starship/releases/latest"] = 403
	Releases.check(http, state, _port(), func(r: Dictionary) -> void: got.append(r))
	check(got[1]["offline"], "a rate limit counts as offline")
	remove(dir)


func test_check_all_stores_tags_and_the_time_once() -> void:
	var dir := temp_dir("rel_all")
	var state := State.load_from(dir.path_join("state.ini"))
	state.set_installed("starship", "v1.0.0")
	var http := FakeHttp.new()
	http.json["https://api.github.com/repos/HarbourMasters/Starship/releases/latest"] = _release_json(
		[_asset("S-Linux.zip")]
	)
	var other := {"id": "gone", "repo": "a/b", "asset_suffix": ".zip"}
	var got := []
	Releases.check_all(
		http, state, [_port(), other], 5000, func(r: Dictionary) -> void: got.append(r)
	)
	eq(got[0]["starship"]["update_available"], true, "installed differs from latest")
	check(not got[0]["gone"]["ok"], "the other port failed alone")
	eq(state.latest_version("starship"), "v2.0.0", "tag stored")
	eq(state.last_check(), 5000, "time stored")
	var all_down := State.load_from(dir.path_join("down.ini"))
	http.offline = true
	Releases.check_all(http, all_down, [_port()], 9000, func(r: Dictionary) -> void: got.append(r))
	eq(all_down.last_check(), 0, "nothing answered, so no check time")
	remove(dir)
