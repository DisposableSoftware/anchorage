extends RefCounted
## Finding a port's latest release on GitHub and deciding when to look (PORT-2, PORT-5,
## PORT-13).
##
## HTTP goes through an object with `fetch_json(url, done)` and `download(...)`: `http.gd`
## in the app, `res://tests/fake_http.gd` in tests. Nothing here blocks: results arrive in
## callbacks.
##
## A release is {tag: String, published_at: String, asset: {name, url, size: int}}.

const API := "https://api.github.com/repos/%s/releases/latest"
const CHECK_INTERVAL := 3600
## Redirects of a release asset go to these hosts (and their subdomains), nowhere else.
const REDIRECT_HOSTS := ["github.com", "githubusercontent.com"]


static func api_url(port: Dictionary) -> String:
	return API % port["repo"]


## Reads the `releases/latest` JSON. {ok: true, release} or {ok: false, error}.
## Prereleases and drafts are not releases here, and an asset whose URL is not a release
## download of the catalog's repo is refused.
static func parse_latest(port: Dictionary, data: Variant) -> Dictionary:
	if not (data is Dictionary and data.get("tag_name") is String and data.get("assets") is Array):
		return {"ok": false, "error": "Unexpected answer from GitHub"}
	var tag: String = data["tag_name"]
	if tag.is_empty() or data.get("draft") == true or data.get("prerelease") == true:
		return {"ok": false, "error": "No stable release"}
	for asset in data["assets"]:
		if not (asset is Dictionary and asset.get("name") is String):
			continue
		if not (asset["name"] as String).to_lower().ends_with(port["asset_suffix"]):
			continue
		var url: Variant = asset.get("browser_download_url")
		if not (url is String and url_allowed(port, url)):
			return {"ok": false, "error": "Release %s has an asset from an unexpected URL" % tag}
		var size := int(asset.get("size", 0))
		if size <= 0:
			return {"ok": false, "error": "Release %s lists an empty asset" % tag}
		return {
			"ok": true,
			"release":
			{
				"tag": tag,
				"published_at": str(data.get("published_at", "")),
				"asset": {"name": asset["name"], "url": url, "size": size},
			},
		}
	return {"ok": false, "error": "Release %s has no Linux download" % tag}


## PORT-13: only release assets of the catalog's own repo, over https from github.com.
static func url_allowed(port: Dictionary, url: String) -> bool:
	var prefix := "https://github.com/%s/releases/download/" % port["repo"]
	if not url.to_lower().begins_with(prefix.to_lower()):
		return false
	var rest := url.substr(prefix.length())
	if rest.is_empty() or rest.contains("..") or rest.contains("\\") or rest.contains("@"):
		return false
	return not (rest.contains(" ") or rest.contains("\n"))


## Where a download may be redirected to: https on GitHub's hosts.
static func redirect_allowed(url: String) -> bool:
	if not url.to_lower().begins_with("https://"):
		return false
	var host := url.substr(8).split("/")[0].split("?")[0].to_lower()
	if host.contains("@") or host.contains(":") or host.is_empty():
		return false
	for allowed in REDIRECT_HOSTS:
		if host == allowed or host.ends_with("." + allowed):
			return true
	return false


## PORT-5: an update is available when the latest tag differs from the installed one.
static func update_available(installed: String, latest: String) -> bool:
	return not installed.is_empty() and not latest.is_empty() and installed != latest


## PORT-5: whether to look for updates. `now` and `last_check` are unix seconds. The
## automatic check (at start) needs `enabled` (`[ports] check_updates`) and an hour since
## the last check; a user's own `refresh` (`manual`) always checks. A last check in the
## future (clock change) counts as due.
static func check_due(last_check: int, now: int, enabled: bool, manual := false) -> bool:
	if manual:
		return true
	if not enabled:
		return false
	return last_check <= 0 or now < last_check or now - last_check >= CHECK_INTERVAL


## Asks GitHub for the port's latest release. `done` gets {ok, release, error, offline}:
## `offline` is true when GitHub could not be reached or answered with a server problem
## (rate limit included), so the caller keeps its last known state.
static func fetch_latest(http: Object, port: Dictionary, done: Callable) -> void:
	http.fetch_json(
		api_url(port),
		func(res: Dictionary) -> void:
			if not res.get("ok", false):
				var no_release: bool = int(res.get("status", 0)) == 404
				(
					done
					. call(
						{
							"ok": false,
							"offline": not no_release,
							"error":
							"No release found" if no_release else str(res.get("error", "")),
						}
					)
				)
				return
			var parsed := parse_latest(port, res.get("data"))
			parsed["offline"] = false
			done.call(parsed)
	)


## Checks one port and remembers the latest tag in `state`. Result as `fetch_latest`, plus
## `update_available`. A failed check leaves `state` alone.
static func check(http: Object, state: Object, port: Dictionary, done: Callable) -> void:
	fetch_latest(
		http,
		port,
		func(result: Dictionary) -> void:
			if result["ok"]:
				state.set_latest(port["id"], result["release"]["tag"])
			result["update_available"] = (
				result["ok"]
				and update_available(state.installed_version(port["id"]), result["release"]["tag"])
			)
			done.call(result)
	)


## Checks the ports one after another (GitHub's unauthenticated limit is low) and, when at
## least one answered, stores `now` as the time of the last check. `done` gets
## {port id: result}.
static func check_all(http: Object, state: Object, ports: Array, now: int, done: Callable) -> void:
	var results := {}
	_check_next(http, state, ports, 0, now, results, done)


static func _check_next(
	http: Object,
	state: Object,
	ports: Array,
	index: int,
	now: int,
	results: Dictionary,
	done: Callable
) -> void:
	if index >= ports.size():
		for result in results.values():
			if result["ok"]:
				state.set_last_check(now)
				break
		done.call(results)
		return
	check(
		http,
		state,
		ports[index],
		func(result: Dictionary) -> void:
			results[ports[index]["id"]] = result
			_check_next(http, state, ports, index + 1, now, results, done)
	)
