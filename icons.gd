extends RefCounted

# The game's icon set: small vector drawings (SVG, white on transparent), turned
# into textures once and cached. Colour them with modulate or a Button's icon
# colour. All drawn on a 64 x 64 grid.

const SVG := {
	"play": '<path d="M20 12 L52 32 L20 52 Z" fill="#fff"/>',
	"target": '<circle cx="32" cy="32" r="18" fill="none" stroke="#fff" stroke-width="4"/><circle cx="32" cy="32" r="4" fill="#fff"/><path d="M32 4 V18 M32 46 V60 M4 32 H18 M46 32 H60" stroke="#fff" stroke-width="4"/>',
	"rifle": '<path d="M4 26 H40 L44 22 H58 V30 H50 L48 34 H40 L34 46 H26 L30 34 H20 L16 42 H8 L10 34 H4 Z" fill="#fff"/><rect x="44" y="16" width="10" height="4" fill="#fff"/>',
	"grenade": '<circle cx="30" cy="38" r="17" fill="#fff"/><rect x="25" y="12" width="12" height="9" fill="#fff"/><path d="M37 15 Q50 12 50 24" fill="none" stroke="#fff" stroke-width="4"/><path d="M17 38 H43 M30 25 V51" stroke="#000" stroke-opacity="0.35" stroke-width="3"/>',
	"knife": '<path d="M8 50 L40 18 L56 8 L46 24 L14 56 Z" fill="#fff"/><path d="M6 46 L18 58" stroke="#fff" stroke-width="5"/>',
	"perk": '<path d="M32 6 L39 24 L58 25 L43 37 L48 56 L32 45 L16 56 L21 37 L6 25 L25 24 Z" fill="#fff"/>',
	"lan": '<rect x="24" y="6" width="16" height="14" rx="2" fill="#fff"/><rect x="6" y="44" width="16" height="14" rx="2" fill="#fff"/><rect x="42" y="44" width="16" height="14" rx="2" fill="#fff"/><path d="M32 20 V32 M14 44 V32 H50 V44" fill="none" stroke="#fff" stroke-width="4"/>',
	"pad": '<path d="M14 20 H50 Q60 20 60 34 L58 46 Q56 54 48 50 L42 44 H22 L16 50 Q8 54 6 46 L4 34 Q4 20 14 20 Z" fill="#fff"/><path d="M18 28 V38 M13 33 H23" stroke="#000" stroke-opacity="0.45" stroke-width="3.5"/><circle cx="44" cy="30" r="3" fill="#000" fill-opacity="0.45"/><circle cx="49" cy="36" r="3" fill="#000" fill-opacity="0.45"/>',
	"gear": '<path d="M28 4 H36 L38 12 L44 15 L51 10 L56 15 L52 22 L54 28 L62 30 V36 L54 38 L52 44 L56 51 L51 56 L44 52 L38 54 L36 62 H28 L26 54 L20 52 L13 56 L8 51 L12 44 L10 38 L2 36 V30 L10 28 L12 22 L8 15 L13 10 L20 15 L26 12 Z" fill="#fff"/><circle cx="32" cy="33" r="9" fill="#000" fill-opacity="0.55"/>',
	"back": '<path d="M28 14 L10 32 L28 50 M10 32 H54" fill="none" stroke="#fff" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>',
	"bomb": '<rect x="10" y="22" width="44" height="28" rx="4" fill="#fff"/><rect x="18" y="28" width="18" height="10" fill="#000" fill-opacity="0.45"/><circle cx="46" cy="33" r="3" fill="#e33"/><path d="M20 22 V14 H44 V22" fill="none" stroke="#fff" stroke-width="4"/>',
	"clock": '<circle cx="32" cy="32" r="24" fill="none" stroke="#fff" stroke-width="5"/><path d="M32 18 V33 L42 40" fill="none" stroke="#fff" stroke-width="5" stroke-linecap="round"/>',
	"heart": '<path d="M24 8 H40 V24 H56 V40 H40 V56 H24 V40 H8 V24 H24 Z" fill="#fff"/>',
	"bullet": '<path d="M24 22 Q24 6 32 4 Q40 6 40 22 Z" fill="#fff"/><rect x="24" y="24" width="16" height="30" fill="#fff"/><rect x="22" y="54" width="20" height="5" fill="#fff"/>',
	"skull": '<path d="M32 6 Q54 6 54 28 Q54 38 46 42 V52 H18 V42 Q10 38 10 28 Q10 6 32 6 Z" fill="#fff"/><circle cx="23" cy="28" r="6" fill="#000" fill-opacity="0.7"/><circle cx="41" cy="28" r="6" fill="#000" fill-opacity="0.7"/><path d="M26 46 V52 M32 46 V52 M38 46 V52" stroke="#000" stroke-opacity="0.6" stroke-width="3"/>',
	"users": '<circle cx="22" cy="20" r="9" fill="#fff"/><path d="M6 50 Q6 32 22 32 Q38 32 38 50 Z" fill="#fff"/><circle cx="44" cy="22" r="8" fill="#fff" fill-opacity="0.75"/><path d="M36 33 Q58 30 58 50 H40 Q40 40 36 33 Z" fill="#fff" fill-opacity="0.75"/>',
	"shield": '<path d="M32 4 L54 12 V30 Q54 50 32 60 Q10 50 10 30 V12 Z" fill="#fff"/>',
	"flash": '<rect x="20" y="14" width="24" height="40" rx="4" fill="#fff"/><rect x="26" y="6" width="12" height="9" fill="#fff"/><path d="M8 20 L2 14 M56 20 L62 14 M8 40 H0 M56 40 H64" stroke="#fff" stroke-width="3"/>',
	"stun": '<rect x="20" y="14" width="24" height="40" rx="4" fill="#fff"/><rect x="26" y="6" width="12" height="9" fill="#fff"/><path d="M26 26 L38 34 L26 42" fill="none" stroke="#000" stroke-opacity="0.5" stroke-width="4"/>',
	"pin": '<path d="M32 60 Q12 36 12 24 A20 20 0 0 1 52 24 Q52 36 32 60 Z" fill="#fff"/><circle cx="32" cy="24" r="7" fill="#000" fill-opacity="0.5"/>',
	"wrench": '<path d="M44 6 A14 14 0 0 0 36 30 L8 58 L14 62 L42 34 A14 14 0 0 0 60 20 L50 24 L44 18 L48 8 Z" fill="#fff"/>',
}

static var _cache := {}


static func tex(name: String, size := 64) -> Texture2D:
	var key := "%s@%d" % [name, size]
	if _cache.has(key):
		return _cache[key]
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">%s</svg>' % SVG.get(name, "")
	var img := Image.new()
	if img.load_svg_from_string(svg, float(size) / 64.0) != OK:
		return null
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t


# A ready-made TextureRect for an icon.
static func rect(name: String, px: float, color := Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex(name, int(px * 2.0))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size = Vector2(px, px)
	r.modulate = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r
