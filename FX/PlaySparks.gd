extends Node3D

class_name  PlaySparks

@export var particles : GPUParticles3D
@export var light : OmniLight3D

func PlaySparks():
	if particles.emitting == false:
		particles.emitting = true
	if particles.emitting == true:
		particles.restart()
	var tween = create_tween()
	tween.tween_property(light, "light_energy", 0.3, 0.1)
	tween.tween_property(light, "light_energy", 0, 0.3) 
