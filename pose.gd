class_name GPose extends RefCounted
## SEAT/POSE CONTRACT (Wave 2 sit + Wave 3 ride) — pose ANY rigged humanoid, cleanly restore it.
##   GPose.sit(character)   -> true  = a Skeleton3D was found and posed seated (thighs raised
##                                     ~85° forward, knees bent ~85° back, torso upright, arms
##                                     slightly forward toward a wheel — when arm bones resolve)
##                           -> false = NO skeleton / no recognizable leg bones. Silent no-op:
##                                     capsule players degrade to the caller's Wave-1 hide path.
##   GPose.ride(character)  -> the ASTRIDE preset (Wave 3 mounts): thighs flexed ~45° FORWARD
##                             at the hip (they drape forward-down over the flanks — without
##                             this the rider read as standing on the animal) AND spread ~40°
##                             OUTWARD (about the character's forward axis, per-side), knees
##                             bent ~90° back so the shins wrap the barrel, torso upright
##                             (spine untouched), hands gently forward to the reins. Same
##                             true/false contract and the SAME "gpose_state" meta snapshot as
##                             sit — one restore path for both.
##   GPose.stand(character)  -> restores the exact pre-sit/pre-ride bone poses + resumes the
##                             paused AnimationPlayer clip. All calls are idempotent.
##
## HOW: per-bone LOCAL pose overrides via Skeleton3D.set_bone_pose_rotation (cleanly reversible —
## the original pose rotations are snapshotted into a meta dict on the character and written back
## by stand(); a resumed AnimationPlayer then re-stomps them anyway). A playing AnimationPlayer is
## PAUSED first (it would fight the pose every frame) and resumed at the same clip + position.
##
## RIG-AGNOSTIC: bones resolve by NAME SUBSTRING, covering both rig families this stack ships:
##   - KayKit Rig_Medium (verified from models/kk_rig_medium_*.glb): hips / spine / chest /
##     upperleg.l / lowerleg.l / upperarm.l / lowerarm.l / wrist.l / hand.l (+ .r) …
##   - Meshy / Mixamo-style 24-bone humanoids: Hips / LeftUpLeg / LeftLeg / LeftArm /
##     LeftForeArm … (any "mixamorig:" prefix is transparent to substring matching)
## Rotation axes are convention-independent: the bend axis is the CHARACTER's lateral (+X) axis
## (stack convention: characters FACE +Z) transformed into skeleton space, and each bone's new
## LOCAL rotation is derived from a snapshot of the skeleton-space global poses — so armature
## orientation, import scale, and bone roll conventions all cancel out.

const META := "gpose_state"       # meta key on the character holding {skel, bones, player, anim, anim_pos}
const THIGH_DEG := -85.0          # thighs raised forward (about character +X; -Y leg -> ~+Z)
const ARM_DEG := -45.0            # upper arms forward toward a wheel
const FOREARM_DEG := -70.0        # forearm TOTAL world pitch (slight extra elbow bend, hands up)
# --- ride (astride) preset ---
# RIDE_THIGH_DEG: hip FLEXION about the lateral axis (same sign convention as sit's THIGH_DEG:
# negative = forward) — composed onto the spread as a global left-multiply, so the whole leg
# drapes forward-down over the flanks. RIDE_SPREAD_DEG: thighs swung OUTWARD about the
# character's FORWARD (+Z) axis, each to its own side (sign from the thigh's lateral offset).
# RIDE_KNEE_DEG: knees bent BACK about the (delta-carried) lateral axis — POSITIVE where sit's
# THIGH_DEG -85 is forward; 90 with the 45° flexion nets the shin ~45° back of vertical, wrapping
# the barrel (70 was tuned for the old unpitched thigh).
const RIDE_THIGH_DEG := -45.0
const RIDE_SPREAD_DEG := 40.0
const RIDE_KNEE_DEG := 90.0
const RIDE_ARM_DEG := -30.0       # upper arms gently forward (reins) — softer than sit's -45
const RIDE_FOREARM_DEG := -55.0   # forearm TOTAL pitch toward the reins
# --- swim (treading) preset (Wave 2) ---
# SWIM_SPINE_DEG: torso pitched FORWARD about the lateral axis. POSITIVE here (not sit's negative):
# the spine bone points UP, and +θ about the character's +X carries an UP-pointing bone toward +Z
# (FORWARD — stack convention faces +Z), the mirror of sit()'s DOWN-pointing-limb negatives.
const SWIM_SPINE_DEG := 15.0


## Pose `character` seated. Returns false (silent no-op) when no skeleton / no leg bones resolve.
static func sit(character: Node3D) -> bool:
	if character == null or not is_instance_valid(character):
		return false
	if character.has_meta(META):
		return true                      # already seated — idempotent
	var skel := _find_skeleton(character)
	if skel == null:
		return false                     # unrigged (capsule) player -> caller's Wave-1 hide fallback
	# ---- resolve bones by substring BEFORE touching anything (a miss must be side-effect free)
	var thighs: Array[int] = []
	var shins: Array[int] = []
	var upperarms: Array[int] = []
	var forearms: Array[int] = []
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i).to_lower()
		if "twist" in bn or "roll" in bn:
			continue                     # helper bones would double-rotate a limb
		if ("upperleg" in bn or "upleg" in bn or "thigh" in bn) and thighs.size() < 2:
			thighs.append(i)
		elif ("lowerleg" in bn or "shin" in bn or "calf" in bn or "leg" in bn) and shins.size() < 2:
			shins.append(i)              # Mixamo "LeftLeg" IS the shin (thigh matched above first)
		elif ("forearm" in bn or "lowerarm" in bn or "elbow" in bn) and forearms.size() < 2:
			forearms.append(i)
		elif ("upperarm" in bn or ("arm" in bn and "armature" not in bn)) and upperarms.size() < 2:
			upperarms.append(i)          # Mixamo "LeftArm" IS the upper arm (forearm matched first)
	if thighs.is_empty():
		return false                     # not a humanoid we understand -> hide fallback
	# ---- pause a playing animation (it would re-stomp the pose every frame)
	var ap := _find_anim_player(character)
	var anim := ""
	var anim_pos := 0.0
	if ap != null and ap.is_playing():
		anim = String(ap.current_animation)
		anim_pos = ap.current_animation_position
		ap.pause()
	# ---- bend axis: the CHARACTER's +X (lateral) axis expressed in skeleton space
	var char_b := character.global_transform.basis.orthonormalized()
	var skel_b := skel.global_transform.basis.orthonormalized()
	var axis := (skel_b.inverse() * (char_b * Vector3.RIGHT)).normalized()
	# ---- snapshot EVERY bone's skeleton-space global basis (pure math below; no dirty-state reads)
	var g := {}
	for i in skel.get_bone_count():
		g[i] = skel.get_bone_global_pose(i).basis.orthonormalized()
	var thigh_rot := Basis(axis, deg_to_rad(THIGH_DEG))
	var arm_rot := Basis(axis, deg_to_rad(ARM_DEG))
	var fore_rot := Basis(axis, deg_to_rad(FOREARM_DEG))
	var orig := {}                       # bone idx -> original local pose Quaternion (for stand())
	# thighs: raise ~85° forward about the lateral axis (global left-multiply, converted to local)
	for t in thighs:
		var tp := skel.get_bone_parent(t)
		var tpg: Basis = (g[tp] as Basis) if tp >= 0 else Basis.IDENTITY
		_set_local(skel, t, tpg.inverse() * (thigh_rot * (g[t] as Basis)), orig)
	# shins: keep their ORIGINAL world orientation -> knees bend ~85° back, feet hang down
	for s in shins:
		var sp := skel.get_bone_parent(s)
		if sp < 0 or not _has_ancestor_in(skel, s, thighs):
			continue                     # shin not under a matched thigh: leave it alone
		var spg: Basis = thigh_rot * (g[sp] as Basis)   # parent chain inherited the thigh delta
		_set_local(skel, s, spg.inverse() * (g[s] as Basis), orig)
	# upper arms: slightly forward (toward a wheel)
	for a in upperarms:
		var ap_i := skel.get_bone_parent(a)
		var apg: Basis = (g[ap_i] as Basis) if ap_i >= 0 else Basis.IDENTITY
		_set_local(skel, a, apg.inverse() * (arm_rot * (g[a] as Basis)), orig)
	# forearms: a touch more pitch than the upper arm (elbow bend, hands raised to the wheel)
	for f in forearms:
		var fp := skel.get_bone_parent(f)
		if fp < 0:
			continue
		var fpg: Basis = (g[fp] as Basis)
		if _has_ancestor_in(skel, f, upperarms):
			fpg = arm_rot * fpg          # parent chain inherited the upper-arm delta
		_set_local(skel, f, fpg.inverse() * (fore_rot * (g[f] as Basis)), orig)
	character.set_meta(META, {
		"skel": skel, "bones": orig, "player": ap, "anim": anim, "anim_pos": anim_pos,
	})
	return true


## Pose `character` ASTRIDE a mount (Wave 3): thighs flexed ~45° forward at the hip + spread
## ~40° outward + knees bent ~90° back, torso upright (spine untouched), hands gently toward
## the reins. Returns false (silent no-op)
## when no skeleton / no leg bones resolve — the caller's hide fallback. Same bone-resolution
## machinery, snapshot meta and stand() restore path as sit(); idempotent (a second ride — or a
## ride on an already-seated character — is a no-op returning true).
static func ride(character: Node3D) -> bool:
	if character == null or not is_instance_valid(character):
		return false
	if character.has_meta(META):
		return true                      # already posed — idempotent
	var skel := _find_skeleton(character)
	if skel == null:
		return false                     # unrigged (capsule) player -> caller's hide fallback
	# ---- resolve bones by substring BEFORE touching anything (a miss must be side-effect free)
	var thighs: Array[int] = []
	var shins: Array[int] = []
	var upperarms: Array[int] = []
	var forearms: Array[int] = []
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i).to_lower()
		if "twist" in bn or "roll" in bn:
			continue                     # helper bones would double-rotate a limb
		if ("upperleg" in bn or "upleg" in bn or "thigh" in bn) and thighs.size() < 2:
			thighs.append(i)
		elif ("lowerleg" in bn or "shin" in bn or "calf" in bn or "leg" in bn) and shins.size() < 2:
			shins.append(i)              # Mixamo "LeftLeg" IS the shin (thigh matched above first)
		elif ("forearm" in bn or "lowerarm" in bn or "elbow" in bn) and forearms.size() < 2:
			forearms.append(i)
		elif ("upperarm" in bn or ("arm" in bn and "armature" not in bn)) and upperarms.size() < 2:
			upperarms.append(i)          # Mixamo "LeftArm" IS the upper arm (forearm matched first)
	if thighs.is_empty():
		return false                     # not a humanoid we understand -> hide fallback
	# ---- pause a playing animation (it would re-stomp the pose every frame)
	var ap := _find_anim_player(character)
	var anim := ""
	var anim_pos := 0.0
	if ap != null and ap.is_playing():
		anim = String(ap.current_animation)
		anim_pos = ap.current_animation_position
		ap.pause()
	# ---- axes in skeleton space: lateral = the CHARACTER's +X, forward = its +Z (stack
	# convention: characters FACE +Z, so forward is Vector3.BACK, not Godot's -Z FORWARD)
	var char_b := character.global_transform.basis.orthonormalized()
	var skel_b := skel.global_transform.basis.orthonormalized()
	var axis := (skel_b.inverse() * (char_b * Vector3.RIGHT)).normalized()
	var fwd := (skel_b.inverse() * (char_b * Vector3.BACK)).normalized()
	# ---- snapshot EVERY bone's skeleton-space global basis (pure math below; no dirty-state reads)
	var g := {}
	for i in skel.get_bone_count():
		g[i] = skel.get_bone_global_pose(i).basis.orthonormalized()
	var arm_rot := Basis(axis, deg_to_rad(RIDE_ARM_DEG))
	var fore_rot := Basis(axis, deg_to_rad(RIDE_FOREARM_DEG))
	var orig := {}                       # bone idx -> original local pose Quaternion (for stand())
	# ---- per-thigh HIP DELTA = forward FLEXION ∘ outward SPREAD (both global left-multiplies;
	# the flexion is left-most so it stays exactly about the character's lateral axis, the sit()
	# convention). Spread: rotating a down-pointing (-Y) leg about +Z_char by +θ swings its tip
	# toward +X_char ((0,-1,0) -> (sinθ, -cosθ, 0)), so a thigh offset to the +X side spreads
	# outward with a POSITIVE angle and the -X side with a NEGATIVE one. Side = the thigh
	# origin's offset along the lateral axis; a rig that centres both thighs (degenerate) falls
	# back to alternating signs so the legs still split.
	var flex := Basis(axis, deg_to_rad(RIDE_THIGH_DEG))
	var hip_delta := {}                  # thigh idx -> that side's combined flexion∘spread Basis
	var flip := 1.0
	for t in thighs:
		var side := skel.get_bone_global_pose(t).origin.dot(axis)
		var sgn := signf(side)
		if absf(side) < 0.001:
			sgn = flip
			flip = -flip
		hip_delta[t] = flex * Basis(fwd, deg_to_rad(RIDE_SPREAD_DEG) * sgn)
	# thighs: flex forward + spread outward (global left-multiply, converted to local — the
	# sit() conversion)
	for t in thighs:
		var tp := skel.get_bone_parent(t)
		var tpg: Basis = (g[tp] as Basis) if tp >= 0 else Basis.IDENTITY
		_set_local(skel, t, tpg.inverse() * ((hip_delta[t] as Basis) * (g[t] as Basis)), orig)
	# shins: bend the knee ~90° BACK about the knee's POST-DELTA lateral axis (the thigh's
	# lateral axis carried through flexion + spread), on top of the inherited hip delta — feet
	# tuck along the mount's flanks. The combined delta replaces the old spread in ALL THREE
	# spots: knee axis, parent-chain carry, and the left-compose.
	for s in shins:
		var sp := skel.get_bone_parent(s)
		var owner_t := _ancestor_of(skel, s, thighs)
		if sp < 0 or owner_t < 0:
			continue                     # shin not under a matched thigh: leave it alone
		var srot: Basis = hip_delta[owner_t] as Basis
		var knee := Basis((srot * axis).normalized(), deg_to_rad(RIDE_KNEE_DEG))
		var spg: Basis = srot * (g[sp] as Basis)   # parent chain inherited the hip delta
		_set_local(skel, s, spg.inverse() * (knee * srot * (g[s] as Basis)), orig)
	# torso upright: spine bones untouched (the pinned astride contract). Arms: same machinery
	# as sit, gentler angles — hands drift forward to the reins instead of a wheel.
	for a in upperarms:
		var ap_i := skel.get_bone_parent(a)
		var apg: Basis = (g[ap_i] as Basis) if ap_i >= 0 else Basis.IDENTITY
		_set_local(skel, a, apg.inverse() * (arm_rot * (g[a] as Basis)), orig)
	for f in forearms:
		var fp := skel.get_bone_parent(f)
		if fp < 0:
			continue
		var fpg: Basis = (g[fp] as Basis)
		if _has_ancestor_in(skel, f, upperarms):
			fpg = arm_rot * fpg          # parent chain inherited the upper-arm delta
		_set_local(skel, f, fpg.inverse() * (fore_rot * (g[f] as Basis)), orig)
	character.set_meta(META, {
		"skel": skel, "bones": orig, "player": ap, "anim": anim, "anim_pos": anim_pos,
	})
	return true


## Pose `character` treading water (Wave 2 swim): the torso pitched ~15° FORWARD so the head/shoulders
## ride above the surface. MINIMAL by design — ONE reversible spine-bone override; arms/legs keep
## their relaxed idle pose (carried forward by the lean), which is the safe capsule-noop-plus-tilt
## allowance from the swim contract. Same snapshot meta + stand() restore path as sit()/ride(); an
## unrigged (capsule) player returns false (the caller hides / no-ops). Idempotent.
static func swim(character: Node3D) -> bool:
	if character == null or not is_instance_valid(character):
		return false
	if character.has_meta(META):
		return true                      # already posed — idempotent
	var skel := _find_skeleton(character)
	if skel == null:
		return false                     # unrigged (capsule) player -> caller's hide fallback
	# lowest torso bone (closest to the hips) — tilting it leans the WHOLE upper body forward while
	# the legs (parented off the hips, not this bone) keep their relaxed pose.
	var spine := -1
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i).to_lower()
		if "twist" in bn or "roll" in bn:
			continue
		if "spine" in bn or "chest" in bn or "torso" in bn:
			spine = i
			break
	if spine < 0:
		return false                     # no torso bone we recognise -> hide fallback
	# ---- pause a playing animation (it would re-stomp the pose every frame)
	var ap := _find_anim_player(character)
	var anim := ""
	var anim_pos := 0.0
	if ap != null and ap.is_playing():
		anim = String(ap.current_animation)
		anim_pos = ap.current_animation_position
		ap.pause()
	# ---- bend axis: the CHARACTER's +X (lateral) axis expressed in skeleton space (sit()'s idiom)
	var char_b := character.global_transform.basis.orthonormalized()
	var skel_b := skel.global_transform.basis.orthonormalized()
	var axis := (skel_b.inverse() * (char_b * Vector3.RIGHT)).normalized()
	# global left-multiply the forward pitch onto the spine's current pose, then convert to local.
	var sp := skel.get_bone_parent(spine)
	var spg: Basis = skel.get_bone_global_pose(sp).basis.orthonormalized() if sp >= 0 else Basis.IDENTITY
	var sg: Basis = skel.get_bone_global_pose(spine).basis.orthonormalized()
	var lean := Basis(axis, deg_to_rad(SWIM_SPINE_DEG))
	var orig := {}
	_set_local(skel, spine, spg.inverse() * (lean * sg), orig)
	character.set_meta(META, {
		"skel": skel, "bones": orig, "player": ap, "anim": anim, "anim_pos": anim_pos,
	})
	return true


## Restore the pre-sit/pre-ride pose + resume the paused animation. No-op if neither ran (idempotent).
static func stand(character: Node3D) -> void:
	if character == null or not is_instance_valid(character):
		return
	if not character.has_meta(META):
		return
	var st: Dictionary = character.get_meta(META)
	character.remove_meta(META)
	var skel = st.get("skel")
	if skel is Skeleton3D and is_instance_valid(skel):
		var bones: Dictionary = st.get("bones", {})
		for idx in bones:
			(skel as Skeleton3D).set_bone_pose_rotation(int(idx), bones[idx])
	var ap = st.get("player")
	var anim := String(st.get("anim", ""))
	if ap is AnimationPlayer and is_instance_valid(ap) and anim != "" and (ap as AnimationPlayer).has_animation(anim):
		(ap as AnimationPlayer).play(anim)
		(ap as AnimationPlayer).seek(float(st.get("anim_pos", 0.0)))


# ---------------- internals ----------------

# Save the original local pose rotation once, then write the new one (orthonormalized -> Quaternion).
static func _set_local(skel: Skeleton3D, idx: int, b: Basis, orig: Dictionary) -> void:
	if not orig.has(idx):
		orig[idx] = skel.get_bone_pose_rotation(idx)
	skel.set_bone_pose_rotation(idx, b.orthonormalized().get_rotation_quaternion())


static func _has_ancestor_in(skel: Skeleton3D, idx: int, pool: Array[int]) -> bool:
	return _ancestor_of(skel, idx, pool) >= 0


# WHICH pool bone is an ancestor of idx (-1 = none) — ride() needs the owning thigh, not just a bool.
static func _ancestor_of(skel: Skeleton3D, idx: int, pool: Array[int]) -> int:
	var p := skel.get_bone_parent(idx)
	while p >= 0:
		if p in pool:
			return p
		p = skel.get_bone_parent(p)
	return -1


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n as Skeleton3D
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


static func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var r := _find_anim_player(c)
		if r != null:
			return r
	return null
