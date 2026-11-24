extends "res://tests/case.gd"
## http.gd against a real local HTTP server (PORT-4, PORT-13): downloads with progress,
## redirects followed by hand (absolute, relative, too many, off GitHub's hosts), a stalled
## download, cancel, the size limit, and JSON with a moved repo. These tests await frames.

const Http := preload("res://src/http.gd")


## A small HTTP/1.1 server on 127.0.0.1, one answer per connection, chosen by path.
## routes[path] = {status, headers: Array[String], body: PackedByteArray, stall: int}; with
## `stall` only that many body bytes are sent and the connection then stays silent.
class Server:
	extends RefCounted

	var routes := {}
	var requests: Array[String] = []
	var _tcp := TCPServer.new()
	var _peers: Array = []

	func start() -> bool:
		return _tcp.listen(0, "127.0.0.1") == OK

	func url(path: String) -> String:
		return "http://127.0.0.1:%d%s" % [_tcp.get_local_port(), path]

	func poll() -> void:
		while _tcp.is_connection_available():
			_peers.append({"peer": _tcp.take_connection(), "text": "", "answered": false})
		for client in _peers:
			var peer: StreamPeerTCP = client["peer"]
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED or client["answered"]:
				continue
			var waiting := peer.get_available_bytes()
			if waiting > 0:
				client["text"] += (
					(peer.get_data(waiting)[1] as PackedByteArray).get_string_from_ascii()
				)
			if client["text"].contains("\r\n\r\n"):
				client["answered"] = true
				_answer(peer, client["text"].split(" ")[1])

	func _answer(peer: StreamPeerTCP, path: String) -> void:
		requests.append(path)
		var route: Dictionary = routes.get(path, {"status": 404})
		var body: PackedByteArray = route.get("body", PackedByteArray())
		var head := "HTTP/1.1 %d X\r\nContent-Length: %d\r\n" % [route["status"], body.size()]
		for header in route.get("headers", []):
			head += header + "\r\n"
		peer.put_data((head + "\r\n").to_ascii_buffer())
		peer.put_data(body.slice(0, route.get("stall", body.size())))

	func stop() -> void:
		for client in _peers:
			client["peer"].disconnect_from_host()
		_tcp.stop()


var _server: Server
var _http: Node
var _dir := ""


func _setup(name: String) -> void:
	_dir = temp_dir(name)
	_server = Server.new()
	check(_server.start(), "the server listens")
	_http = Http.new()
	_http.allow_http = true
	(Engine.get_main_loop() as SceneTree).root.add_child(_http)


func _teardown() -> void:
	_http.get_parent().remove_child(_http)
	_http.free()
	_server.stop()
	remove(_dir)


## Polls the server every frame until `box` has a result (at most `seconds`).
func _until(box: Dictionary, seconds := 5.0) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not box.has("result") and Time.get_ticks_msec() < end:
		_server.poll()
		await tree.process_frame
	check(box.has("result"), "%s: an answer within %s s" % [current, seconds])


func _bytes(count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(count)
	for i in count:
		out[i] = i % 251
	return out


func _route(status: int, body := PackedByteArray(), headers := [], stall := -1) -> Dictionary:
	var route := {"status": status, "body": body, "headers": headers}
	if stall >= 0:
		route["stall"] = stall
	return route


## Starts a download of `path` and waits for `done`. {result, progress: [[got, total]]}.
func _download(path: String, expected := 0, seconds := 5.0) -> Dictionary:
	var box := {"progress": []}
	_http.download(
		_server.url(path),
		_dir.path_join("file"),
		func(got: int, total: int) -> void: box["progress"].append([got, total]),
		func(result: Dictionary) -> void: box["result"] = result,
		expected
	)
	await _until(box, seconds)
	return box


func test_a_download_follows_absolute_and_relative_redirects() -> void:
	_setup("http_redirect")
	var body := _bytes(300_000)
	_server.routes["/file"] = _route(200, body)
	_server.routes["/relative"] = _route(302, PackedByteArray(), ["Location: /file"])
	_server.routes["/absolute"] = _route(
		301, PackedByteArray(), ["Location: " + _server.url("/relative")]
	)
	var box := await _download("/absolute", body.size())
	eq(box.get("result", {}).get("ok"), true, "downloaded: %s" % str(box.get("result")))
	eq(_server.requests, ["/absolute", "/relative", "/file"], "both hops followed by hand")
	eq(FileAccess.get_file_as_bytes(_dir.path_join("file")), body, "the body is the file")
	check(not box["progress"].is_empty(), "progress reported")
	check(
		box["progress"].all(func(p: Array) -> bool: return p[1] == body.size() and p[0] <= p[1]),
		"bytes done of the full size: %s" % str(box["progress"].slice(0, 3))
	)
	_teardown()


func test_too_many_redirects_and_foreign_hosts_are_refused() -> void:
	_setup("http_hops")
	_server.routes["/loop"] = _route(302, PackedByteArray(), ["Location: /loop"])
	var box := await _download("/loop")
	eq(box.get("result", {}).get("error"), "Refused a redirect", "a redirect loop ends")
	eq(_server.requests.size(), Http.MAX_HOPS + 1, "the first request and MAX_HOPS hops")
	_server.requests.clear()
	_server.routes["/away"] = _route(
		302, PackedByteArray(), ["Location: https://evil.example#.github.com/x"]
	)
	box = await _download("/away")
	eq(box.get("result", {}).get("error"), "Refused a redirect", "off GitHub's hosts (PORT-13)")
	_server.routes["/odd"] = _route(302, PackedByteArray(), ["Location: file"])
	box = await _download("/odd")
	eq(box.get("result", {}).get("error"), "Refused a redirect", "a path-relative Location")
	_teardown()


func test_a_stalled_download_fails() -> void:
	_setup("http_stall")
	_http.stall_seconds = 0.5
	_server.routes["/slow"] = _route(200, _bytes(10_000), [], 100)
	var box := await _download("/slow", 10_000)
	eq(box.get("result", {}).get("error"), "The download stalled", "nothing for 0.5 s")
	eq(box.get("result", {}).get("cancelled"), false, "a failure, not a cancel")
	_teardown()


func test_cancel_stops_a_running_download() -> void:
	_setup("http_cancel")
	_server.routes["/slow"] = _route(200, _bytes(10_000), [], 100)
	var box := {"progress": []}
	_http.download(
		_server.url("/slow"),
		_dir.path_join("file"),
		func(got: int, total: int) -> void:
			box["progress"].append([got, total])
			if got > 0:
				_http.cancel_download(),
		func(result: Dictionary) -> void: box["result"] = result
	)
	await _until(box)
	eq(box.get("result", {}).get("cancelled"), true, "cancelled")
	eq(box.get("result", {}).get("ok"), false, "not ok")
	var again := await _download("/missing")
	eq(again.get("result", {}).get("status"), 404, "the next download runs after a cancel")
	_teardown()


func test_a_body_larger_than_the_release_says_is_refused() -> void:
	_setup("http_limit")
	_server.routes["/big"] = _route(200, _bytes(5000))
	var box := await _download("/big", 100)
	eq(
		box.get("result", {}).get("error"),
		"The download is larger than the release says",
		"body_size_limit is the release size"
	)
	_teardown()


func test_json_follows_a_moved_repo_and_refuses_foreign_redirects() -> void:
	_setup("http_json")
	_server.routes["/api"] = _route(200, '{"tag_name": "1.0"}'.to_utf8_buffer())
	_server.routes["/moved"] = _route(301, PackedByteArray(), ["Location: /api"])
	_server.routes["/away"] = _route(
		301, PackedByteArray(), ["Location: https://api.github.com.evil.example/x"]
	)
	_server.routes["/loop"] = _route(301, PackedByteArray(), ["Location: /loop"])
	var box := {}
	_http.fetch_json(_server.url("/moved"), func(r: Dictionary) -> void: box["result"] = r)
	await _until(box)
	eq(box.get("result", {}).get("data"), {"tag_name": "1.0"}, "followed to the new place")
	for path in ["/away", "/loop"]:
		box = {}
		_http.fetch_json(_server.url(path), func(r: Dictionary) -> void: box["result"] = r)
		await _until(box)
		eq(box.get("result", {}).get("error"), "Refused a redirect", path)
	eq(_server.requests.count("/loop"), Http.MAX_HOPS + 1, "at most MAX_HOPS hops")
	box = {}
	_server.routes["/broken"] = _route(200, "not json".to_utf8_buffer())
	_http.fetch_json(_server.url("/broken"), func(r: Dictionary) -> void: box["result"] = r)
	await _until(box)
	eq(box.get("result", {}).get("error"), "GitHub sent unreadable data", "a bad body")
	_teardown()


func test_text_has_a_size_limit_and_checked_redirects() -> void:
	_setup("http_text")
	_server.routes["/catalog"] = _route(200, '{"ports": []}'.to_utf8_buffer())
	_server.routes["/big"] = _route(200, "x".repeat(2048).to_utf8_buffer())
	_server.routes["/moved"] = _route(302, PackedByteArray(), ["Location: /catalog"])
	_server.routes["/away"] = _route(
		302, PackedByteArray(), ["Location: https://raw.githubusercontent.com.evil.example/x"]
	)
	var box := {}
	_http.fetch_text(_server.url("/moved"), 1024, func(r: Dictionary) -> void: box["result"] = r)
	await _until(box)
	eq(box.get("result", {}).get("text"), '{"ports": []}', "followed and read as text")
	box = {}
	_http.fetch_text(_server.url("/big"), 1024, func(r: Dictionary) -> void: box["result"] = r)
	await _until(box)
	eq(box.get("result", {}).get("ok"), false, "over the limit (PORT-19)")
	eq(box.get("result", {}).get("error"), "The answer is too large", "says why")
	box = {}
	_http.fetch_text(_server.url("/away"), 1024, func(r: Dictionary) -> void: box["result"] = r)
	await _until(box)
	eq(box.get("result", {}).get("error"), "Refused a redirect", "off GitHub's hosts")
	_teardown()


func test_plain_http_is_only_for_this_machine() -> void:
	var http := Http.new()
	http.allow_http = true
	check(http._url_ok("http://127.0.0.1:8080/x"), "a local test server")
	for url in [
		"http://example.com/x",
		"http://127.0.0.1.evil.example:80/x",
		"http://127.0.0.1@evil.example:80/x",
		"http://localhost:80/x",
	]:
		check(not http._url_ok(url), "refused: " + url)
	http.allow_http = false
	check(not http._url_ok("http://127.0.0.1:8080/x"), "not without allow_http")
	http.free()
