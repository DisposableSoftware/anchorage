extends RefCounted
## The catalog fetched from the repository, so the port list grows without an app release
## (PORT-18 .. PORT-21). `Ports` calls these; the merge itself is `Catalog.merge`.
##
##   CatalogUpdate.url() -> String                 URL, or the ANCHORAGE_CATALOG_URL test hook
##   CatalogUpdate.fetch(http, url, done)          done({ok, catalog (Catalog.parse), text, error})
##   CatalogUpdate.read_cache(path) -> Dictionary  Catalog.parse of the cache, ok false if none
##   CatalogUpdate.write_cache(path, text) -> bool atomic (temp file, then rename)
##   CatalogUpdate.notice(names, newer) -> String  "2 new ports: Foo, Bar"
##
## HTTP goes through an object with http.gd's `fetch_text(url, max_bytes, done)`; tests pass
## res://tests/fake_http.gd.

const Catalog := preload("res://src/catalog.gd")

const URL := (
	"https://raw.githubusercontent.com" + "/DisposableSoftware/anchorage/main/app/data/ports.json"
)
const ENV := "ANCHORAGE_CATALOG_URL"
## What the test hook may point at: raw.githubusercontent.com, or a server on this machine.
const OVERRIDE := (
	"^(https://raw\\.githubusercontent\\.com/[A-Za-z0-9_./-]+"
	+ "|http://127\\.0\\.0\\.1:[0-9]{1,5}/[A-Za-z0-9_./-]*)$"
)


## PORT-18: the repository's catalog, or ANCHORAGE_CATALOG_URL (tests and development) when
## it is an allowed URL.
static func url() -> String:
	var override := OS.get_environment(ENV)
	if override.is_empty():
		return URL
	if not override_allowed(override):
		push_warning("%s ignored: only raw.githubusercontent.com or 127.0.0.1" % ENV)
		return URL
	return override


static func override_allowed(value: String) -> bool:
	var found := RegEx.create_from_string(OVERRIDE).search(value)
	# PCRE's `$` also matches before a final line break.
	return found != null and found.get_end() == value.length() and not value.contains("..")


## $XDG_CACHE_HOME/anchorage/catalog.json (PORT-21).
static func default_cache() -> String:
	return OS.get_cache_dir().path_join("anchorage").path_join("catalog.json")


## PORT-19: fetches at most Catalog.MAX_BYTES and checks it as a fetched catalog. A failure
## of any kind is {ok: false, error}, which changes nothing.
static func fetch(http: Object, from: String, done: Callable) -> void:
	http.fetch_text(
		from,
		Catalog.MAX_BYTES,
		func(res: Dictionary) -> void:
			if not res.get("ok", false):
				done.call({"ok": false, "error": str(res.get("error", "")), "text": ""})
				return
			var text: String = res.get("text", "")
			var catalog := Catalog.parse(text, true)
			if not catalog["ok"]:
				done.call({"ok": false, "error": catalog["errors"][0], "text": ""})
				return
			done.call({"ok": true, "catalog": catalog, "text": text, "error": ""})
	)


## The cached catalog, checked like a fetched one; ok false when it is missing or broken.
static func read_cache(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "ports": [], "errors": PackedStringArray(), "version": 0, "newer": []}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > Catalog.MAX_BYTES:
		return Catalog.parse("", true)
	var text := file.get_as_text()
	file.close()
	return Catalog.parse(text, true)


## Writes `text` beside `path` and renames it over, so a kill never leaves half a file.
static func write_cache(path: String, text: String) -> bool:
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return false
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	if DirAccess.rename_absolute(tmp, path) != OK:
		DirAccess.remove_absolute(tmp)
		return false
	return true


## PORT-23: "1 new port: Foo", "2 new ports: Foo, Bar", and a second line when `newer`
## entries were skipped: "1 more needs a newer Anchorage". "" when there is nothing to say.
static func notice(names: Array, newer: int) -> String:
	var lines := PackedStringArray()
	if not names.is_empty():
		var noun := "new port" if names.size() == 1 else "new ports"
		lines.append("%d %s: %s" % [names.size(), noun, ", ".join(PackedStringArray(names))])
	if newer > 0:
		var verb := "needs" if newer == 1 else "need"
		var what := (
			"%d more" % newer
			if not names.is_empty()
			else ("1 port" if newer == 1 else "%d ports" % newer)
		)
		lines.append("%s %s a newer Anchorage" % [what, verb])
	return "\n".join(lines)
