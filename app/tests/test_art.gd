extends "res://tests/case.gd"
## Cover art (ART-3, ART-4, ART-6) over fake HTTP and temp folders. Card behaviour is in
## test_home.

const Art := preload("res://src/art.gd")
const Ports := preload("res://src/ports.gd")
const Http := preload("res://src/http.gd")
const FakeHttp := preload("res://tests/fake_http.gd")
const URL := "https://cdn2.steamgriddb.com/grid/aaaa.png"
const URL2 := "https://cdn2.steamgriddb.com/grid/bbbb.png"


## Holds a download until `release`, so a test can look at the state before the art arrives.
class HeldHttp:
	extends "res://tests/fake_http.gd"

	var held: Array = []

	func download(
		url: String, dest: String, progress: Callable, done: Callable, expected := 0
	) -> void:
		held.append([url, dest, progress, done, expected])

	func release() -> void:
		var args: Array = held.pop_front()
		super.download(args[0], args[1], args[2], args[3], args[4])


var _dir := ""
var _got := {}


func _setup(name: String) -> FakeHttp:
	_dir = temp_dir(name)
	_got = {}
	return FakeHttp.new()


func _on_ready(id: String, texture: Texture2D) -> void:
	_got[id] = texture


func _png(name: String, width := 64, height := 30) -> String:
	var path := _dir.path_join(name)
	Image.create(width, height, false, Image.FORMAT_RGB8).save_png(path)
	return path


func _write(name: String, bytes: PackedByteArray) -> String:
	var path := _dir.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()
	return path


func _fetch(http: RefCounted, items: Array) -> RefCounted:
	var art: RefCounted = Art.new(http, _dir.path_join("cache"))
	art.fetch(items, _on_ready)
	return art


func _cached(art: RefCounted) -> Array:
	return Array(DirAccess.get_files_at(art.dir))


func test_art_is_downloaded_once_and_named_by_the_hash_of_its_url() -> void:
	var http := _setup("art_once")
	http.files[URL] = _png("a.png")
	var art := _fetch(http, [{"id": "soh", "url": URL}])
	eq(http.requests, [URL], "one request (ART-3)")
	eq(_cached(art), [URL.sha256_text()], "cached under the hash of the URL, no .part left")
	check(_got["soh"] is Texture2D, "the texture is delivered")
	eq(_got["soh"].get_size(), Vector2(64, 30), "at its own size")
	remove(_dir)


func test_a_cache_hit_makes_no_request_and_a_changed_url_fetches_again() -> void:
	var http := _setup("art_cache")
	http.files[URL] = _png("a.png")
	http.files[URL2] = _png("b.png", 80, 40)
	_fetch(http, [{"id": "soh", "url": URL}])
	http.requests.clear()
	_got.clear()
	var art := _fetch(http, [{"id": "soh", "url": URL}])
	eq(http.requests, [], "an unchanged URL never fetches (ART-3)")
	eq(_got["soh"].get_size(), Vector2(64, 30), "but still shows the cached art")
	_fetch(http, [{"id": "soh", "url": URL2}])
	eq(http.requests, [URL2], "a changed URL fetches again")
	eq(_got["soh"].get_size(), Vector2(80, 40), "and shows the new art")
	eq(_cached(art).size(), 2, "named by URL hash, so the old file is simply unused")
	remove(_dir)


func test_a_cached_file_that_no_longer_decodes_is_replaced() -> void:
	var http := _setup("art_corrupt")
	http.files[URL] = _png("a.png")
	var art := Art.new(http, _dir.path_join("cache"))
	DirAccess.make_dir_recursive_absolute(art.dir)
	var file := FileAccess.open(art.path_for(URL), FileAccess.WRITE)
	file.store_string("not a picture")
	file.close()
	art.fetch([{"id": "soh", "url": URL}], _on_ready)
	eq(http.requests, [URL], "fetched again")
	check(_got.has("soh"), "and shown")
	remove(_dir)


func test_art_comes_only_from_steamgriddb_cdn_over_https() -> void:
	var http := _setup("art_hosts")
	var bad := [
		"https://example.com/grid/a.png",
		"http://cdn2.steamgriddb.com/grid/a.png",
		"https://cdn2.steamgriddb.com.example.com/grid/a.png",
		"https://cdn2.steamgriddb.com@example.com/grid/a.png",
		"https://cdn2.steamgriddb.com:8443/grid/a.png",
		"https://www.steamgriddb.com/grid/a.png",
		"https://cdn2.steamgriddb.com",
		"https://cdn2.steamgriddb.com/",
	]
	var items := []
	for url in bad:
		http.files[url] = _png("x.png")
		items.append({"id": "x", "url": url})
	var art := _fetch(http, items)
	eq(http.requests, [], "no request for a wrong host (ART-4)")
	eq(_got, {}, "and nothing shown")
	eq(_cached(art), [], "and nothing cached")
	for url in ["https://cdn2.steamgriddb.com/grid/a.png", "https://cdn.steamgriddb.com/a.webp"]:
		check(Art.url_allowed(url), url)
	remove(_dir)


func test_a_redirect_off_the_art_hosts_is_refused() -> void:
	var http := Http.new()
	http.redirect_check = Art.url_allowed
	check(http._redirect_ok("https://cdn.steamgriddb.com/grid/a.png"), "art host")
	check(not http._redirect_ok("https://github.com/x/y"), "not a release host")
	check(not http._redirect_ok("https://example.com/a.png"), "not another host")
	var releases := Http.new()
	check(releases._redirect_ok("https://github.com/x/y"), "release downloads keep theirs")
	check(not releases._redirect_ok("https://cdn.steamgriddb.com/a.png"), "and only theirs")
	http.free()
	releases.free()


func test_a_file_over_5_mib_is_refused_and_deleted() -> void:
	var http := _setup("art_big")
	var bytes := PackedByteArray()
	bytes.resize(Art.MAX_BYTES + 1)
	http.files[URL] = _write("big.png", bytes)
	var art := _fetch(http, [{"id": "soh", "url": URL}])
	eq(_got, {}, "not shown (ART-4)")
	eq(_cached(art), [], "and deleted")
	remove(_dir)


func test_something_that_is_not_an_image_is_deleted() -> void:
	var http := _setup("art_text")
	http.files[URL] = _write("page.html", "<html>not found</html>".to_utf8_buffer())
	var art := _fetch(http, [{"id": "soh", "url": URL}])
	eq(_got, {}, "not shown (ART-4)")
	eq(_cached(art), [], "deleted")
	remove(_dir)


func test_a_truncated_image_is_deleted() -> void:
	var http := _setup("art_cut")
	var bytes := FileAccess.get_file_as_bytes(_png("a.png", 200, 100))
	http.files[URL] = _write("cut.png", bytes.slice(0, 40))
	var art := _fetch(http, [{"id": "soh", "url": URL}])
	eq(_got, {}, "not shown")
	eq(_cached(art), [], "deleted")
	remove(_dir)


func test_pictures_over_4096_pixels_are_refused() -> void:
	var http := _setup("art_dims")
	http.files[URL] = _png("wide.png", 4097, 2)
	var art := _fetch(http, [{"id": "wide", "url": URL}])
	eq(_got, {}, "4097 wide is refused (ART-4)")
	eq(_cached(art), [], "and deleted")
	http.files[URL2] = _png("edge.png", 4096, 2)
	_fetch(http, [{"id": "edge", "url": URL2}])
	check(_got.has("edge"), "4096 wide is fine")
	remove(_dir)


func test_a_small_file_that_claims_a_huge_picture_is_refused_before_decoding() -> void:
	_setup("art_forged")
	var png := FileAccess.get_file_as_bytes(_png("a.png"))
	png.encode_u32(16, 0)
	png[16] = 0x00
	png[17] = 0x01
	png[18] = 0x86
	png[19] = 0xA0
	check(Art.decode(_write("forged.png", png)) == null, "100000 pixels wide (ART-4)")
	check(Art.decode(_png("ok.png")) != null, "the real one decodes")
	remove(_dir)


func test_png_jpeg_and_webp_decode_and_sizes_come_from_the_header() -> void:
	_setup("art_formats")
	var image := Image.create(120, 50, false, Image.FORMAT_RGB8)
	image.fill(Color.from_hsv(0.3, 0.5, 0.8))
	image.save_png(_dir.path_join("a.png"))
	image.save_jpg(_dir.path_join("a.jpg"))
	image.save_webp(_dir.path_join("lossy.webp"))
	image.save_webp(_dir.path_join("lossless.webp"), false, 1.0)
	for name in ["a.png", "a.jpg", "lossy.webp", "lossless.webp"]:
		var path := _dir.path_join(name)
		var bytes := FileAccess.get_file_as_bytes(path)
		var kind := Art._kind(bytes)
		eq(Art._size(bytes, kind), Vector2i(120, 50), "%s header size" % name)
		var decoded := Art.decode(path)
		check(decoded != null, "%s decodes" % name)
		if decoded != null:
			eq(decoded.get_size(), Vector2i(120, 50), "%s decoded size" % name)
	remove(_dir)


func test_a_failed_download_shows_nothing_and_leaves_nothing() -> void:
	var http := _setup("art_fail")
	http.status[URL] = 500
	http.files[URL2] = _png("b.png")
	var art := _fetch(http, [{"id": "a", "url": URL}, {"id": "b", "url": URL2}])
	eq(http.requests, [URL, URL2], "the next one is still tried")
	eq(_got.keys(), ["b"], "only the good one shows (ART-6)")
	eq(_cached(art), [URL2.sha256_text()], "no partial file left")
	http.offline = true
	_got.clear()
	_fetch(http, [{"id": "c", "url": URL}])
	eq(_got, {}, "offline shows nothing")
	remove(_dir)


func _catalog_with_art() -> Array:
	var out := []
	for id in ["alpha", "beta"]:
		var port := {
			"id": id,
			"name": id.capitalize(),
			"game": "Game " + id,
			"description": "About " + id,
			"repo": "test/" + id,
			"asset_suffix": "-linux.zip",
			"archive": [id + ".o2r"],
			"launch": {"executable": id + ".appimage", "cwd": "data", "args": []},
			"extra_files": [],
			"rom_place": "data_dir",
			"rom_file": id + ".z64",
			"roms": [{"label": "US", "sha1": "0".repeat(40)}],
		}
		if id == "alpha":
			port["art"] = {"url": URL, "author": "A", "source": "S", "style": "alternate"}
		out.append(port)
	return out


func _make_ports(http: RefCounted) -> Node:
	var ports: Node = Ports.new()
	ports.root = _dir.path_join("ports")
	ports.state_path = _dir.path_join("state/state.ini")
	ports.roms_dir = _dir.path_join("roms")
	ports.art_dir = _dir.path_join("art")
	ports.check_updates = false
	ports.catalog = _catalog_with_art()
	ports.http = http
	ports.threaded = false
	(Engine.get_main_loop() as SceneTree).root.add_child(ports)
	return ports


func _free_ports(ports: Node) -> void:
	ports.get_parent().remove_child(ports)
	ports.free()
	remove(_dir)


func test_ports_starts_the_art_at_start_and_announces_it() -> void:
	var http := _setup("art_ports")
	http.files[URL] = _png("a.png")
	var ports := _make_ports(http)
	check(ports.info("alpha").art is Texture2D, "info(id).art is a texture (ART-3, ART-6)")
	check(ports.info("beta").art == null, "a port without art has null")
	eq(http.requests, [URL], "only the port with art is fetched")
	check(ports.info("alpha").error.is_empty(), "no error")
	_free_ports(ports)


func test_ports_without_the_art_has_null_and_no_error_and_changed_when_it_arrives() -> void:
	var held := HeldHttp.new()
	_setup("art_ports_late")
	held.files[URL] = _png("a.png")
	var seen := []
	var ports: Node = Ports.new()
	ports.root = _dir.path_join("ports")
	ports.state_path = _dir.path_join("state/state.ini")
	ports.roms_dir = _dir.path_join("roms")
	ports.art_dir = _dir.path_join("art")
	ports.check_updates = false
	ports.catalog = _catalog_with_art()
	ports.http = held
	ports.threaded = false
	ports.changed.connect(func(id: String) -> void: seen.append(id))
	(Engine.get_main_loop() as SceneTree).root.add_child(ports)
	var before: Dictionary = ports.info("alpha")
	check(before.art == null, "no art while it downloads (ART-6)")
	check(before.error.is_empty(), "and no error")
	seen.clear()
	held.release()
	check(ports.info("alpha").art is Texture2D, "the art arrived")
	check("alpha" in seen, "changed(alpha) was emitted")
	var after: Dictionary = ports.info("alpha")
	for key in before:
		if key != "art":
			eq(after[key], before[key], "%s did not change" % key)
	_free_ports(ports)


func test_offline_ports_shows_the_monogram_and_no_error() -> void:
	var http := _setup("art_ports_offline")
	http.offline = true
	var ports := _make_ports(http)
	check(ports.info("alpha").art == null, "no art offline (ART-6)")
	check(ports.info("alpha").error.is_empty(), "no error")
	_free_ports(ports)
