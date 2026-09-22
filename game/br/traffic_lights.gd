extends Node
## Светофоры: фазы «север-юг» / «восток-запад» (визуально, NPC пока их не ждёт).

const CYCLE := 22.0

var city = null
var night := 0.0
var _t := 0.0


func _process(delta: float) -> void:
	_t = fmod(_t + delta, CYCLE)
	if city == null or city.traffic_mats.is_empty():
		return
	var ns_g := _t < 9.0
	var ns_y := _t >= 9.0 and _t < 11.0
	var ew_g := _t >= 11.0 and _t < 20.0
	var ew_y := _t >= 20.0 and _t < 22.0
	var glow := 1.8 + night * 1.4
	var m = city.traffic_mats
	m["ns_g"].emission_energy_multiplier = glow if ns_g else 0.05
	m["ns_y"].emission_energy_multiplier = glow if ns_y else 0.05
	m["ns_r"].emission_energy_multiplier = glow if (not ns_g and not ns_y) else 0.05
	m["ew_g"].emission_energy_multiplier = glow if ew_g else 0.05
	m["ew_y"].emission_energy_multiplier = glow if ew_y else 0.05
	m["ew_r"].emission_energy_multiplier = glow if (not ew_g and not ew_y) else 0.05
