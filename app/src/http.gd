extends Node
## The real HTTP layer on `HTTPRequest` (PORT-2, PORT-4, PORT-13). Add it to the scene
## tree, then call:
##
##   fetch_json(url, done)
##       done({ok, status, data, error}) with the parsed JSON body in `data`.
##   download(url, dest, progress, done, expected_size := 0)
##       Streams the body to `dest` (HTTPRequest.download_file), polled once a frame.
##       progress(bytes_done, bytes_total) every frame; bytes_total is -1 when unknown.
##       done({ok, status, error, cancelled}). One download at a time.
##   cancel_download()
##       Stops the running download; `done` still fires, with cancelled = true.
##
## GitHub asset URLs redirect to a CDN, and the API redirects for a moved repo. Redirects are
## followed by hand (max_redirects = 0), at most MAX_HOPS, so each hop can be checked against
## `Releases.redirect_allowed` (https, GitHub hosts). Tests use `res://tests/fake_http.gd`,
## which has the same three methods; `test_http.gd` runs this file against a local server.

const Releases := preload("res://src/releases.gd")
const USER_AGENT := "Anchorage"
const MAX_HOPS := 5
const CHUNK_BYTES := 1 << 20

## Lets http:// URLs through, for a local test server. Never set by the app.
var allow_http := false
## A download that receives nothing for this long fails.
var stall_seconds := 60.0
## The limit for one API call.
var timeout_seconds := 30.0
## Decides where a redirect may go; empty means GitHub's hosts (`Releases.redirect_allowed`).
## The cover art loader sets its own, so art redirects never reach other hosts (ART-4).
var redirect_check := Callable()

var _job := {}
var _request: HTTPRequest
var _stalled := 0.0
var _last_bytes := -1


func _ready() -> void:
	set_process(false)


## Redirects (a moved repo) are followed by hand, like downloads, and checked the same way.
func fetch_json(url: String, done: Callable, hops := 0) -> void:
	if not _url_ok(url):
		done.call({"ok": false, "status": 0, "error": "Refused URL"})
		return
	var request := HTTPRequest.new()
	request.max_redirects = 0
	request.timeout = timeout_seconds
	add_child(request)
	request.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
			request.queue_free()
			if _is_redirect(result, code):
				var target := _resolve(url, _header(headers, "location"))
				if hops >= MAX_HOPS or target.is_empty() or not _redirect_ok(target):
					done.call({"ok": false, "status": code, "error": "Refused a redirect"})
				else:
					fetch_json(target, done, hops + 1)
				return
			done.call(_json_result(result, code, body))
	)
	var headers := [
		"User-Agent: " + USER_AGENT,
		"Accept: application/vnd.github+json",
		"X-GitHub-Api-Version: 2022-11-28",
	]
	var err := request.request(url, headers)
	if err != OK:
		request.queue_free()
		done.call({"ok": false, "status": 0, "error": error_string(err)})


func download(
	url: String, dest: String, progress: Callable, done: Callable, expected_size := 0
) -> void:
	if not _job.is_empty():
		done.call({"ok": false, "status": 0, "error": "Another download is running"})
		return
	_job = {
		"dest": dest,
		"progress": progress,
		"done": done,
		"expected": expected_size,
		"hops": 0,
		"cancelled": false,
	}
	_start(url)


func cancel_download() -> void:
	if _job.is_empty():
		return
	_job["cancelled"] = true
	if _request != null:
		_request.cancel_request()
	_finish({"ok": false, "status": 0, "error": "Cancelled", "cancelled": true})


func _process(delta: float) -> void:
	if _job.is_empty() or _request == null:
		return
	var got := _request.get_downloaded_bytes()
	var total := _request.get_body_size()
	if total <= 0:
		total = _job["expected"] if _job["expected"] > 0 else -1
	_job["progress"].call(got, total)
	if got != _last_bytes:
		_last_bytes = got
		_stalled = 0.0
	else:
		_stalled += delta
		if _stalled > stall_seconds:
			_request.cancel_request()
			_finish({"ok": false, "status": 0, "error": "The download stalled"})


func _start(url: String) -> void:
	if not _url_ok(url):
		_finish({"ok": false, "status": 0, "error": "Refused URL"})
		return
	_request = HTTPRequest.new()
	_request.max_redirects = 0
	# Not use_threads: its thread blocks in a socket read, so cancelling a stalled download
	# (cancel_request joins the thread) froze the main loop. Polled from the main loop, a
	# read never blocks; the large chunk keeps one read per frame fast enough.
	_request.use_threads = false
	_request.download_chunk_size = CHUNK_BYTES
	_request.download_file = _job["dest"]
	if _job["expected"] > 0:
		_request.body_size_limit = _job["expected"]
	add_child(_request)
	_request.request_completed.connect(_on_completed.bind(url))
	_last_bytes = -1
	_stalled = 0.0
	var err := _request.request(url, ["User-Agent: " + USER_AGENT, "Accept: */*"])
	if err != OK:
		_finish({"ok": false, "status": 0, "error": error_string(err)})
		return
	set_process(true)


func _on_completed(
	result: int, code: int, headers: PackedStringArray, _body: PackedByteArray, url: String
) -> void:
	if _job.is_empty():
		return
	if _is_redirect(result, code):
		var target := _resolve(url, _header(headers, "location"))
		if _job["hops"] >= MAX_HOPS or target.is_empty() or not _redirect_ok(target):
			_finish({"ok": false, "status": code, "error": "Refused a redirect"})
			return
		_job["hops"] += 1
		_free_request()
		_start(target)
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish({"ok": false, "status": code, "error": _result_text(result)})
	elif code != 200:
		_finish({"ok": false, "status": code, "error": "HTTP %d" % code})
	else:
		_finish({"ok": true, "status": code, "error": ""})


func _finish(result: Dictionary) -> void:
	var done: Callable = _job.get("done", Callable())
	_job = {}
	set_process(false)
	_free_request()
	result["cancelled"] = result.get("cancelled", false)
	if done.is_valid():
		done.call(result)


func _free_request() -> void:
	if _request != null:
		_request.queue_free()
		_request = null


func _url_ok(url: String) -> bool:
	return url.begins_with("https://") or (allow_http and url.begins_with("http://"))


func _redirect_ok(url: String) -> bool:
	if allow_http and url.begins_with("http://"):
		return true
	if redirect_check.is_valid():
		return redirect_check.call(url)
	return Releases.redirect_allowed(url)


static func _is_redirect(result: int, code: int) -> bool:
	return result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED and code in [301, 302, 303, 307, 308]


static func _header(headers: PackedStringArray, name: String) -> String:
	var prefix := name.to_lower() + ":"
	for header in headers:
		if header.to_lower().begins_with(prefix):
			return header.substr(prefix.length()).strip_edges()
	return ""


## `location` against the URL it answered, for a relative redirect.
static func _resolve(url: String, location: String) -> String:
	if location.is_empty() or location.begins_with("http"):
		return location
	if not location.begins_with("/"):
		return ""
	var scheme_end := url.find("://") + 3
	var path_start := url.find("/", scheme_end)
	return (url if path_start < 0 else url.substr(0, path_start)) + location


static func _json_result(result: int, code: int, body: PackedByteArray) -> Dictionary:
	if result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "status": 0, "error": _result_text(result)}
	if code != 200:
		var hint := " (rate limited?)" if code in [403, 429] else ""
		return {"ok": false, "status": code, "error": "GitHub answered HTTP %d%s" % [code, hint]}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {"ok": false, "status": code, "error": "GitHub sent unreadable data"}
	return {"ok": true, "status": code, "data": json.data, "error": ""}


static func _result_text(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "Could not connect"
		HTTPRequest.RESULT_TIMEOUT:
			return "The connection timed out"
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "The download is larger than the release says"
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Could not write the download"
	return "Network error %d" % result
