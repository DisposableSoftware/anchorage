extends RefCounted
## A stand-in for `res://src/http.gd` that answers from memory and local files, and calls
## back at once. Same methods.
##
##   json["<url>"] = <parsed JSON>          fetch_json answers it with status 200
##   text["<url>"] = "<body>"               fetch_text answers it, up to its max_bytes
##   status["<url>"] = 500                  fetch_json / download answer with that status
##   files["<url>"] = "/local/path"         download copies the file
##   offline = true                         everything fails like a lost connection

var json := {}
var text := {}
var status := {}
var files := {}
var offline := false
## Bytes copied between two progress calls.
var chunk := 4
var requests: Array[String] = []
var _cancelled := false


func fetch_json(url: String, done: Callable) -> void:
	requests.append(url)
	if offline:
		done.call({"ok": false, "status": 0, "error": "Could not connect"})
	elif status.has(url):
		done.call({"ok": false, "status": status[url], "error": "HTTP %d" % status[url]})
	elif json.has(url):
		done.call({"ok": true, "status": 200, "data": json[url], "error": ""})
	else:
		done.call({"ok": false, "status": 404, "error": "HTTP 404"})


func fetch_text(url: String, max_bytes: int, done: Callable) -> void:
	requests.append(url)
	if offline:
		done.call({"ok": false, "status": 0, "error": "Could not connect"})
	elif status.has(url):
		done.call({"ok": false, "status": status[url], "error": "HTTP %d" % status[url]})
	elif not text.has(url):
		done.call({"ok": false, "status": 404, "error": "HTTP 404"})
	elif (text[url] as String).to_utf8_buffer().size() > max_bytes:
		done.call({"ok": false, "status": 200, "error": "The answer is too large"})
	else:
		done.call({"ok": true, "status": 200, "text": text[url], "error": ""})


func download(
	url: String, dest: String, progress: Callable, done: Callable, _expected_size := 0
) -> void:
	requests.append(url)
	_cancelled = false
	if offline:
		done.call({"ok": false, "status": 0, "error": "Could not connect", "cancelled": false})
		return
	if status.has(url) or not files.has(url):
		var code: int = status.get(url, 404)
		done.call({"ok": false, "status": code, "error": "HTTP %d" % code, "cancelled": false})
		return
	var data := FileAccess.get_file_as_bytes(files[url])
	var out := FileAccess.open(dest, FileAccess.WRITE)
	var pos := 0
	while pos < data.size():
		var end := mini(pos + chunk, data.size())
		out.store_buffer(data.slice(pos, end))
		pos = end
		progress.call(pos, data.size())
		if _cancelled:
			out.close()
			done.call({"ok": false, "status": 0, "error": "Cancelled", "cancelled": true})
			return
	out.close()
	done.call({"ok": true, "status": 200, "error": "", "cancelled": false})


func cancel_download() -> void:
	_cancelled = true
