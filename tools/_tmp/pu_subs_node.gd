extends Node
func _ready() -> void:
	Game.scan_data()
	var args := OS.get_cmdline_user_args()
	var dir := DataPath.find_ci(Game.pu_root, "Carmodel")
	var crp := Crp.load_file(DataPath.find_ci(dir, args[0] + ".crp"))
	for art in crp.articles:
		if art.name in args.slice(1):
			var keys: Array = art.subs.keys()
			var out := []
			for k: String in keys:
				var e: Crp.Entry = art.subs[k]
				out.append("%s(len%d,n%d)" % [k, e.length, e.count])
			print(art.name, ": ", " ".join(out))
			var b := crp.sub(art, "Base")
			var nn := crp.sub(art, "$n", 1)
			print("  $n ", crp.data.slice(nn.offset, nn.offset + 160).hex_encode())
			var pp := crp.sub(art, "pr", 4096)
			print("  pr ", crp.data.slice(pp.offset, pp.offset + 64).hex_encode())
			print("  base ", crp.data.slice(b.offset, b.offset + b.length).hex_encode())
	get_tree().quit()
