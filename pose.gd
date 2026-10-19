extends RefCounted

# One first-person pose: where the camera sits, how it is tilted, where the
# weapon is held and how lively the movement is. Every movement state owns
# one of these; the player blends from the current pose to the next.

var eye := 1.65                 # camera height above the feet, metres
var cam := Vector3.ZERO         # extra camera offset
var cam_rot := Vector3.ZERO     # camera tilt in degrees: pitch, yaw, roll
var gun := Vector3.ZERO         # weapon position relative to the camera
var gun_rot := Vector3.ZERO     # weapon rotation in degrees
var bob := 0.0                  # how far each step moves the view, metres
var stride := 1.9               # step phase per metre travelled (radians)
var swing := 0.0                # arm swing with the stride, degrees
var lag := 1.0                  # how far the weapon trails behind the body
var fov := 0.0                  # added field of view, degrees
var left_free := 0.0            # 1 = support hand off the weapon
var blend := 0.2                # seconds to blend into this pose


func mixed(to: RefCounted, k: float) -> RefCounted:
	var p = get_script().new()
	p.eye = lerpf(eye, to.eye, k)
	p.cam = cam.lerp(to.cam, k)
	p.cam_rot = cam_rot.lerp(to.cam_rot, k)
	p.gun = gun.lerp(to.gun, k)
	p.gun_rot = gun_rot.lerp(to.gun_rot, k)
	p.bob = lerpf(bob, to.bob, k)
	p.stride = lerpf(stride, to.stride, k)
	p.swing = lerpf(swing, to.swing, k)
	p.lag = lerpf(lag, to.lag, k)
	p.fov = lerpf(fov, to.fov, k)
	p.left_free = lerpf(left_free, to.left_free, k)
	p.blend = to.blend
	return p
