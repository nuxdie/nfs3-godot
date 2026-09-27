class_name Qfs
## RefPack ("QFS") decompression used by EA's .qfs/.fsh archives.


static func is_compressed(data: PackedByteArray) -> bool:
	return data.size() >= 5 and (data[0] & 0xFE) == 0x10 and data[1] == 0xFB


static func decompress(src: PackedByteArray) -> PackedByteArray:
	if not is_compressed(src):
		return src
	var out_size := (src[2] << 16) | (src[3] << 8) | src[4]
	var out := PackedByteArray()
	out.resize(out_size)
	var i := 8 if (src[0] & 0x01) else 5
	var o := 0
	var n := src.size()
	while i < n and src[i] < 0xFC:
		var c := src[i]
		var lit := 0
		var cnt := 0
		var off := 0
		if (c & 0x80) == 0:
			var b1 := src[i + 1]
			lit = c & 0x03
			cnt = ((c & 0x1C) >> 2) + 3
			off = ((c >> 5) << 8) + b1 + 1
			i += 2
		elif (c & 0x40) == 0:
			var b1 := src[i + 1]
			var b2 := src[i + 2]
			lit = (b1 >> 6) & 0x03
			cnt = (c & 0x3F) + 4
			off = (b1 & 0x3F) * 256 + b2 + 1
			i += 3
		elif (c & 0x20) == 0:
			var b1 := src[i + 1]
			var b2 := src[i + 2]
			var b3 := src[i + 3]
			lit = c & 0x03
			cnt = ((c >> 2) & 0x03) * 256 + b3 + 5
			off = ((c & 0x10) << 12) + 256 * b1 + b2 + 1
			i += 4
		else:
			lit = (c & 0x1F) * 4 + 4
			i += 1
			for k in lit:
				out[o + k] = src[i + k]
			i += lit
			o += lit
			continue
		for k in lit:
			out[o + k] = src[i + k]
		i += lit
		o += lit
		# Back-reference; may overlap its own output, so copy byte by byte.
		var from := o - off
		for k in cnt:
			out[o + k] = out[from + k]
		o += cnt
	if i < n and o < out_size:
		var tail := src[i] & 0x03
		for k in tail:
			out[o + k] = src[i + 1 + k]
	return out
