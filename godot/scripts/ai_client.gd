extends Node
## The Node.js proxy holds credentials. The game only knows its local URL.
@export var endpoint: String = "http://127.0.0.1:4173/api/world"

func request(task: String, payload: Dictionary) -> Dictionary:
	var http = HTTPRequest.new()
	http.timeout = 35.0
	add_child(http)
	var body = payload.duplicate(true)
	body.task = task
	var error = http.request(endpoint, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if error != OK:
		http.queue_free()
		return {"error": "无法连接本地 AI 代理"}
	var response = await http.request_completed
	http.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		return {"error": "AI 请求失败或超时"}
	var parser = JSON.new()
	if parser.parse(response[3].get_string_from_utf8()) != OK:
		return {"error": "AI 响应不是有效 JSON"}
	var parsed = parser.data
	if not parsed is Dictionary:
		return {"error": "AI 响应格式无效"}
	if response[1] != 200:
		return {"error": str(parsed.get("error", "代理请求失败"))}
	return parsed
