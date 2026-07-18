extends Node
## KONG ISLAND director — owns the TITLE SCREEN (STORY / FREE ROAM), the story campaign chain,
## region ambience + entry toasts, the Kong boss bar, camera shake, and the victory screen.
## The shared engine (main.gd) calls: setup(main), world_ready(), input_locked(), _shake_cam(t),
## toggle_stable_panel(), and (Kong hook) on_kill(type). Everything UI is anchor/container-laid
## against the LIVE viewport (art.md RESPONSIVE FILL) and rebuilt on resize.

const CHAIN := ["q1_land", "q2_wall", "q3_gorge", "q4_pits", "q5_jungle", "q6_horn", "q7_lair", "q8_ann", "q9_kong"]
const STAGE_TOAST := {
	"q1_land": "Stage 1 - Landfall: pilot the steamship to the beach",
	"q2_wall": "Stage 2 - The Great Wall: drive off the guardians, take the Gate Key",
	"q3_gorge": "Stage 3 - Cross the rope bridge over the gorge",
	"q4_pits": "Stage 4 - Survive the pit of giant insects",
	"q5_jungle": "Stage 5 - Battle through jungle and swamp",
	"q6_horn": "Stage 6 - Find the Horn of Kong in the temple ruins",
	"q7_lair": "Stage 7 - Climb the volcano to Kong's lair",
	"q8_ann": "Stage 8 - Rescue Ann from the nest",
	"q9_kong": "Final Stage - Face King Kong",
}

var main = null
var mode := ""            # "" until chosen; "story" | "roam"
var _world_ready := false
var _won := false

var _layer: CanvasLayer = null
var _title_root: Control = null
var _win_root: Control = null
var _quest_lbl: Label = null
var _toast_lbl: Label = null
var _boss_root: Control = null
var _boss_fill: ColorRect = null
var _boss_name: Label = null

var _story_idx := -1
var _regions: Array = []
var _cur_region := ""
var _amb_cur := ""
var _music_cur := ""
var _region_t := 0.0
var _shake := 0.0
var _boarded_ship := false


func setup(m) -> void:
	main = m
	_layer = CanvasLayer.new()
	_layer.layer = 150   # under the AudioManager tap overlay (200), over the HUD (0)
	add_child(_layer)
	_build_title()
	# this game has no stable/taming — hide the engine's default STABLE button
	if main._hud_btns.has("stable"):
		(main._hud_btns["stable"] as Button).visible = false
	_quest_lbl = Label.new()
	_quest_lbl.add_theme_font_size_override("font_size", 17)
	_quest_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	_quest_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_quest_lbl.add_theme_constant_override("shadow_offset_y", 1)
	_quest_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_quest_lbl.visible = false
	main.hud_layer.add_child(_quest_lbl)
	_toast_lbl = Label.new()
	_toast_lbl.add_theme_font_size_override("font_size", 30)
	_toast_lbl.add_theme_color_override("font_color", Color(1.0, 0.97, 0.88))
	_toast_lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_toast_lbl.add_theme_constant_override("shadow_offset_y", 2)
	_toast_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_lbl.modulate.a = 0.0
	main.hud_layer.add_child(_toast_lbl)
	_build_boss_bar()
	main.quest.objective_changed.connect(_on_quest_changed)
	get_window().size_changed.connect(_relayout)
	_relayout()


func world_ready() -> void:
	_world_ready = true
	var regs = main.world_data.get("regions", [])
	if regs is Array:
		_regions = regs
	if mode != "":
		_apply_mode()


func input_locked() -> bool:
	return (_title_root != null and _title_root.visible) or (_win_root != null and _win_root.visible)


func toggle_stable_panel() -> void:
	pass   # no stable in this game


func _shake_cam(t: float) -> void:
	_shake = maxf(_shake, t)


# ---------------- title screen ----------------

func _build_title() -> void:
	_title_root = Control.new()
	_title_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_title_root)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.06, 0.94)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var kicker := Label.new()
	kicker.text = "AN EXPEDITION TO THE UNCHARTED ISLAND"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_font_size_override("font_size", 18)
	kicker.add_theme_color_override("font_color", Color(0.75, 0.72, 0.6))
	box.add_child(kicker)
	var title := Label.new()
	title.text = "KONG ISLAND"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 84)
	title.add_theme_color_override("font_color", Color(0.98, 0.88, 0.55))
	title.add_theme_color_override("font_shadow_color", Color(0.35, 0.12, 0.02, 0.9))
	title.add_theme_constant_override("shadow_offset_y", 4)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "Dinosaurs. Tribes. Storms. And the King himself."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.8, 0.82, 0.78))
	box.add_child(sub)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 26)
	box.add_child(spacer)
	box.add_child(_mode_button("STORY", "A guided expedition: sea, wall, gorge, pits, jungle - to Kong's lair",
		func() -> void: _choose("story")))
	box.add_child(_mode_button("FREE ROAM", "The whole island open - drive, sail, fly, hunt every creature",
		func() -> void: _choose("roam")))
	var hint := Label.new()
	hint.text = "Left side: move joystick   |   Right side: drag to look\nWASD + mouse on desktop   |   SPACE jumps"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
	box.add_child(hint)


func _mode_button(txt: String, caption: String, cb: Callable) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var b := Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(360, 84)
	b.add_theme_font_size_override("font_size", 38)
	b.pressed.connect(cb)
	wrap.add_child(b)
	var c := Label.new()
	c.text = caption
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_theme_font_size_override("font_size", 14)
	c.add_theme_color_override("font_color", Color(0.6, 0.63, 0.6))
	wrap.add_child(c)
	return wrap


func _choose(m: String) -> void:
	mode = m
	AudioManager.play_sfx("ui")
	if _title_root != null:
		_title_root.visible = false
	if _world_ready:
		_apply_mode()


func _apply_mode() -> void:
	if mode == "story":
		_quest_lbl.visible = true
		# cinematic opening: fog + storm at sea; the world's day/weather cycle resumes at landfall
		main.weather.apply({"time": "sunrise", "weather": "storm"})
		_story_idx = 0
		main.quest.start(CHAIN[0])
		_refresh_quest_lbl()
		_toast(String(STAGE_TOAST[CHAIN[0]]), 5.0)
		_board_steamship()
	else:
		# FREE ROAM: every story gate opens; spawn at the expedition camp with the jeep
		main.rpg.add_item("gate_key")
		main.rpg.add_item("lair_horn")
		var camp = main.world_data.get("camp_pos", null)
		if camp is Array and (camp as Array).size() >= 2:
			var cx := float(camp[0])
			var cz := float(camp[1])
			var cy: float = main.chunk_manager._ground_y(cx, cz) if main.chunk_manager != null else 0.0
			main.player.global_position = Vector3(cx, cy + 0.3, cz)
		_toast("The island is yours - explore, hunt, sail, fly. Kong waits at the volcano.", 5.0)
	_start_music("heroic_fantasy")


func _board_steamship() -> void:
	if _boarded_ship:
		return
	for v in main.vehicles:
		if is_instance_valid(v) and String(v.get_meta("spec", {}).get("name", "")) == "Steamship":
			_boarded_ship = true
			v.enter(main.player)
			break


# ---------------- story chain ----------------

func _on_quest_changed() -> void:
	_refresh_quest_lbl()
	if mode != "story" or _story_idx < 0 or _story_idx >= CHAIN.size():
		return
	var cur := String(CHAIN[_story_idx])
	if String(main.quest.st[cur].status) == "done":
		AudioManager.play_sfx("pickup", -2.0, 1.15)
		if cur == "q1_land":
			main._apply_weather(main.world_data)   # landfall: hand the sky back to the island's living cycle
		_story_idx += 1
		if _story_idx < CHAIN.size():
			var nxt := String(CHAIN[_story_idx])
			main.quest.start(nxt)
			_toast(String(STAGE_TOAST[nxt]), 5.0)
			_refresh_quest_lbl()


func _refresh_quest_lbl() -> void:
	if _quest_lbl == null or mode != "story":
		return
	var txt: String = main.quest.current_objective()
	_quest_lbl.text = txt.replace(" / ", "\n") if txt != "" else ""


# ---------------- kong / victory ----------------

func on_kill(type: String) -> void:
	if type == "kong" and not _won:
		_won = true
		_show_victory()


func _show_victory() -> void:
	AudioManager.play_music(load("res://audio/victory.ogg"), -5.0)
	_music_cur = "victory"
	_win_root = Control.new()
	_win_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_win_root)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.04, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_win_root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var t := Label.new()
	t.text = "KONG HAS FALLEN"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 64)
	t.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	box.add_child(t)
	var s := Label.new()
	s.text = ("Ann is safe. The expedition sails home with a story no one will believe."
		if mode == "story" else "The king of the island has been bested.")
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	s.add_theme_font_size_override("font_size", 20)
	s.add_theme_color_override("font_color", Color(0.85, 0.87, 0.82))
	box.add_child(s)
	var b := Button.new()
	b.text = "KEEP EXPLORING"
	b.custom_minimum_size = Vector2(320, 72)
	b.add_theme_font_size_override("font_size", 30)
	b.pressed.connect(func() -> void:
		_win_root.visible = false
		_start_music("heroic_fantasy"))
	box.add_child(b)


func _build_boss_bar() -> void:
	_boss_root = Control.new()
	_boss_root.visible = false
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.hud_layer.add_child(_boss_root)
	_boss_name = Label.new()
	_boss_name.text = "KING KONG"
	_boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_name.add_theme_font_size_override("font_size", 24)
	_boss_name.add_theme_color_override("font_color", Color(1.0, 0.45, 0.3))
	_boss_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_boss_root.add_child(_boss_name)
	var bbg := ColorRect.new()
	bbg.name = "bbg"
	bbg.color = Color(0, 0, 0, 0.55)
	_boss_root.add_child(bbg)
	_boss_fill = ColorRect.new()
	_boss_fill.color = Color(0.9, 0.2, 0.12)
	_boss_root.add_child(_boss_fill)


func _relayout() -> void:
	if main == null:
		return
	var vp: Vector2 = main.get_viewport().get_visible_rect().size
	if _quest_lbl != null:
		_quest_lbl.position = Vector2(12, 140)
		_quest_lbl.size = Vector2(minf(430.0, vp.x * 0.55), 200)
	if _toast_lbl != null:
		_toast_lbl.position = Vector2(vp.x * 0.1, vp.y * 0.16)
		_toast_lbl.size = Vector2(vp.x * 0.8, 120)
	if _boss_root != null:
		var w := minf(520.0, vp.x * 0.7)
		_boss_root.position = Vector2((vp.x - w) * 0.5, 44)
		_boss_name.position = Vector2(0, -32)
		_boss_name.size = Vector2(w, 30)
		var bbg := _boss_root.get_node_or_null("bbg") as ColorRect
		if bbg != null:
			bbg.size = Vector2(w, 16)
		if _boss_fill != null:
			_boss_fill.size = Vector2(w, 16)
		_boss_root.set_meta("bar_w", w)


func _toast(msg: String, hold := 3.0) -> void:
	if _toast_lbl == null:
		return
	_toast_lbl.text = msg
	_toast_lbl.modulate.a = 0.0
	var tw := _toast_lbl.create_tween()
	tw.tween_property(_toast_lbl, "modulate:a", 1.0, 0.35)
	tw.tween_interval(hold)
	tw.tween_property(_toast_lbl, "modulate:a", 0.0, 0.7)


# ---------------- per-frame: regions, boss bar, camera shake ----------------

func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	# camera shake (decaying random offset on the Camera3D h/v offsets)
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.2)
		var a := _shake * 0.35
		main.cam.h_offset = randf_range(-a, a)
		main.cam.v_offset = randf_range(-a, a)
	elif main.cam.h_offset != 0.0 or main.cam.v_offset != 0.0:
		main.cam.h_offset = 0.0
		main.cam.v_offset = 0.0
	if not _world_ready or mode == "":
		return
	_region_t += delta
	if _region_t >= 0.6:
		_region_t = 0.0
		_update_region()
		_update_boss_bar()
	if mode == "story" and not _boarded_ship:
		_board_steamship()   # vehicles may spawn a beat after world_ready


func _update_region() -> void:
	var p: Vector3 = main.player.global_position
	var best := ""
	var best_d := 1e12
	var best_rec: Dictionary = {}
	for r0 in _regions:
		if typeof(r0) != TYPE_DICTIONARY:
			continue
		var r := r0 as Dictionary
		var c = r.get("center", [0, 0])
		if not (c is Array) or (c as Array).size() < 2:
			continue
		var d := Vector2(p.x - float(c[0]), p.z - float(c[1])).length()
		if d < float(r.get("radius", 40.0)) and d < best_d:
			best_d = d
			best = String(r.get("name", ""))
			best_rec = r
	if best == "" or best == _cur_region:
		return
	_cur_region = best
	_toast(best, 2.2)
	var amb := String(best_rec.get("ambient", ""))
	if amb == "auto_jungle":
		amb = "night_crickets" if String(main.weather.time_state) == "night" else "forest_birds"
	if amb != "" and amb != _amb_cur:
		var path := "res://audio/" + amb + ".ogg"
		if ResourceLoader.exists(path):
			_amb_cur = amb
			AudioManager.play_ambient(load(path))
	var mus := String(best_rec.get("music", ""))
	if mus != "" and not _won:
		_start_music(mus)
	elif mus == "" and _music_cur == "boss_dramatic" and not _won:
		_start_music("heroic_fantasy")


func _start_music(name_: String) -> void:
	if _music_cur == name_:
		return
	var path := "res://audio/" + name_ + ".ogg"
	if ResourceLoader.exists(path):
		_music_cur = name_
		AudioManager.play_music(load(path))


func _update_boss_bar() -> void:
	var streamer = main.chunk_manager if main.chunk_mode else main.scene_manager
	if streamer == null:
		return
	var kong = null
	for e in streamer.enemies:
		if is_instance_valid(e) and String(e.get("kind")) == "kong" and not bool(e.get("dead")):
			kong = e
			break
	var show := false
	if kong != null:
		var d: float = main.player.global_position.distance_to((kong as Node3D).global_position)
		show = d < 70.0
		if show and _boss_fill != null:
			var w := float(_boss_root.get_meta("bar_w", 520.0))
			_boss_fill.size.x = w * clampf(float(kong.get("hp")) / maxf(1.0, float(kong.get("hp_max"))), 0.0, 1.0)
	if _boss_root != null and _boss_root.visible != show:
		_boss_root.visible = show
