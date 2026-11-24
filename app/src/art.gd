extends RefCounted
## Cover art for the port cards (ART-3, ART-4). `fetch` downloads the catalog's art one
## file at a time into a cache folder and hands each decoded texture to a callback; nothing
## here shows an error, because a card without art falls back to its monogram (ART-6).
##
##   var art := Art.new(http, dir)        http: http.gd's `download`; dir: the cache folder
##   art.offload = my_offload             optional: offload(work, finished) runs `work` off
##                                        the main thread and calls `finished(result)` on it
##   art.fetch([{id, url}], ready)        ready(id, texture) once per file that is usable
##
## A file is named by the hash of its URL, so a changed URL fetches again and an unchanged
## one never does. The art comes from SteamGridDB's CDN only, at most MAX_BYTES, and must
## decode as PNG, JPEG or WebP of at most MAX_SIDE x MAX_SIDE; anything else is deleted.
## The decoder reads the size from the file header first, so a small file that claims a huge
## picture is refused before it is decoded.

const HOSTS := ["cdn2.steamgriddb.com", "cdn.steamgriddb.com"]
const MAX_BYTES := 5 * 1024 * 1024
const MAX_SIDE := 4096

var http: Object
var dir := ""
var offload := Callable()

var _queue: Array = []
var _running := false
var _ready := Callable()


func _init(download_with: Object, cache_dir: String) -> void:
	http = download_with
	dir = cache_dir


## True for an https URL on one of SteamGridDB's CDN hosts, without a port or user info.
static func url_allowed(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var host := url.substr(8).split("/")[0]
	return host in HOSTS and url.length() > 8 + host.length() + 1


func path_for(url: String) -> String:
	return dir.path_join(url.sha256_text())


func fetch(items: Array, ready: Callable) -> void:
	_ready = ready
	_queue.append_array(items)
	if not _running:
		DirAccess.make_dir_recursive_absolute(dir)
		_next()


func _next() -> void:
	if _queue.is_empty():
		_running = false
		return
	_running = true
	var item: Dictionary = _queue.pop_front()
	var url: String = item["url"]
	if not url_allowed(url):
		_next()
		return
	var path := path_for(url)
	if not FileAccess.file_exists(path):
		_download(item)
		return
	_decode(
		path,
		func(image: Image) -> void:
			if image == null:
				DirAccess.remove_absolute(path)
				_download(item)
			else:
				_deliver(item, image)
	)


func _download(item: Dictionary) -> void:
	var url: String = item["url"]
	var part := path_for(url) + ".part"
	var progress := func(_got: int, _total: int) -> void: pass
	http.download(
		url,
		part,
		progress,
		func(result: Dictionary) -> void: _downloaded(item, part, result),
		MAX_BYTES
	)


func _downloaded(item: Dictionary, part: String, result: Dictionary) -> void:
	if not result.get("ok", false) or _file_size(part) > MAX_BYTES:
		DirAccess.remove_absolute(part)
		_next()
		return
	_decode(
		part,
		func(image: Image) -> void:
			if image == null:
				DirAccess.remove_absolute(part)
				_next()
				return
			DirAccess.rename_absolute(part, path_for(item["url"]))
			_deliver(item, image)
	)


func _deliver(item: Dictionary, image: Image) -> void:
	if _ready.is_valid():
		_ready.call(item["id"], ImageTexture.create_from_image(image))
	_next()


func _decode(path: String, finished: Callable) -> void:
	var work := decode.bind(path)
	if offload.is_valid():
		offload.call(work, finished)
	else:
		finished.call(work.call())


## The image in `path` with mipmaps (the card scales it down), or null when it is too big,
## not a PNG, JPEG or WebP, or does not decode. Safe on a worker thread.
static func decode(path: String) -> Image:
	if _file_size(path) > MAX_BYTES:
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var kind := _kind(bytes)
	var size := _size(bytes, kind)
	if size.x <= 0 or size.y <= 0 or size.x > MAX_SIDE or size.y > MAX_SIDE:
		return null
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	match kind:
		"png":
			err = image.load_png_from_buffer(bytes)
		"jpeg":
			err = image.load_jpg_from_buffer(bytes)
		"webp":
			err = image.load_webp_from_buffer(bytes)
	if err != OK or image.is_empty() or image.get_width() > MAX_SIDE:
		return null
	if image.get_height() > MAX_SIDE:
		return null
	image.generate_mipmaps()
	return image


static func _file_size(path: String) -> int:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_length() if file != null else 0


static func _kind(bytes: PackedByteArray) -> String:
	if bytes.size() < 16:
		return ""
	if bytes.slice(0, 8) == PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]):
		return "png"
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return "jpeg"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		if bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
			return "webp"
	return ""


## The picture size the file header claims, (0, 0) when it cannot be read.
static func _size(bytes: PackedByteArray, kind: String) -> Vector2i:
	match kind:
		"png":
			if bytes.size() >= 24:
				return Vector2i(_be32(bytes, 16), _be32(bytes, 20))
		"jpeg":
			return _jpeg_size(bytes)
		"webp":
			return _webp_size(bytes)
	return Vector2i.ZERO


static func _be32(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


static func _jpeg_size(bytes: PackedByteArray) -> Vector2i:
	var at := 2
	while at + 4 <= bytes.size():
		if bytes[at] != 0xFF:
			return Vector2i.ZERO
		var marker := bytes[at + 1]
		if marker == 0xFF:
			at += 1
			continue
		if marker == 0x01 or (marker >= 0xD0 and marker <= 0xD9):
			at += 2
			continue
		var is_frame := marker >= 0xC0 and marker <= 0xCF and not marker in [0xC4, 0xC8, 0xCC]
		if is_frame:
			if at + 9 > bytes.size():
				return Vector2i.ZERO
			var height := (bytes[at + 5] << 8) | bytes[at + 6]
			var width := (bytes[at + 7] << 8) | bytes[at + 8]
			return Vector2i(width, height)
		at += 2 + ((bytes[at + 2] << 8) | bytes[at + 3])
	return Vector2i.ZERO


static func _webp_size(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 30:
		return Vector2i.ZERO
	match bytes.slice(12, 16).get_string_from_ascii():
		"VP8 ":
			return Vector2i(bytes.decode_u16(26) & 0x3FFF, bytes.decode_u16(28) & 0x3FFF)
		"VP8L":
			var bits := bytes.decode_u32(21)
			return Vector2i((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
		"VP8X":
			var width := bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)
			var height := bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)
			return Vector2i(width + 1, height + 1)
	return Vector2i.ZERO
