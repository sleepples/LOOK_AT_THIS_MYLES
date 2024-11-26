extends CharacterBody3D

const AK_ROTATION_SPEED: float = 3.0
const CAMERA_ROTATION_SPEED: float = 1.5
const FALL_DAMAGE_THRESHOLD: float = 10.0
const NORMAL_HEIGHT: float = 1.0

@onready var wall_run_left = $NECK/Raycasts/WallRunLeft
@onready var wall_run_right = $NECK/Raycasts/WallRunRight


@export_subgroup("SLIDING")
@export var SLIDE_HEIGHT: float = 0.3
@export var SLIDE_SPEED: float = 30.0
@export var SLIDE_FRICTION: float = 0.25
@export var SLIDE_DURATION: float = 1.0
@export var SLIDE_TRANSITION_SPEED: float = 7.5  # Speed at which the slide transition occurs

@export_subgroup("CROUCHING")
@export var CROUCH_SPEED: float = 3.5
@export var CROUCH_HEIGHT: float = 0.5
@export var CROUCH_TIME_ACUMMALTED: float = 0.0
@export var CROUCH_TRANSITION_SPEED: float = 5.0  # Speed at which the crouch transition occurs

@export_subgroup("MOVEMENT")
@export var DEFAULT_SPEED: float = 5.5
@export var OLD_VELOCITY: float = 0.0

@export_subgroup("SPRINTING")
@export var SPRINT_MULTIPLIER: float = 2.5
@export var SPRINT_TIME_ACUMMALTED: float = 0.0

@export_subgroup("JUMPING")
@export var JUMP_VELOCITY: float = 4.0

@export_subgroup("EXTRA")
@export var SLIDING_FOV: float = 90.0
@export var CROUCH_FOV: float = 70.0
@export var NORMAL_FOV: float = 80.0  # Normal Field of View
@export var SPRINT_FOV: float = 105.0  # Sprinting Field of View
@export var FOV_TRANSITION_SPEED: float = 5.0  # Speed at which the FOV transition occurs

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
@onready var NECK = $NECK
@onready var CAMERA = $NECK/Camera3D

@onready var COLLISION_SHAPE = $CollisionShape3D


var IS_CROUCHING = false
var IS_SLIDING = false
var SLIDE_TIMER = 0.0
var SLIDE_DIRECTION: Vector3 = Vector3.ZERO
var currently_wallrunning = false
var JUMPS_LEFT = 1
@onready var dash_ray_cast = $NECK/Raycasts/DashRayCast


func _ready():
	pass
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			NECK.rotate_y(-event.relative.x * 0.01)
			CAMERA.rotate_x(-event.relative.y * 0.01)
			CAMERA.rotation.x = clamp(CAMERA.rotation.x, deg_to_rad(-30), deg_to_rad(60))
	
func _physics_process(delta: float) -> void:
	can_wallrun(delta)
	move_and_slide()
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
		
	# Handle arrow keys
	if Input.is_action_pressed("ui_left"):
		NECK.rotate_y(AK_ROTATION_SPEED * delta)
	
	if Input.is_action_pressed("ui_right"):
		NECK.rotate_y(-AK_ROTATION_SPEED * delta)

	if Input.is_action_pressed("ui_up"):
		CAMERA.rotate_x(AK_ROTATION_SPEED * delta)
	
	if Input.is_action_pressed("ui_down"):
		CAMERA.rotate_x(-AK_ROTATION_SPEED * delta)
	
	# Handle Jump
	if Input.is_action_just_pressed("ui_accept") and JUMPS_LEFT > 0:
		velocity.y = JUMP_VELOCITY
		JUMPS_LEFT -= 1
	
	if is_on_floor():
		JUMPS_LEFT = 1;
	
	if Input.is_action_just_pressed("Dash"):
		var DashTween = create_tween()
		#velocity += CAMERA.get_global_transform().basis.z * -20
		DashTween.tween_property(self, "position", dash_ray_cast.position, 0.45)
		
		
	# Sprinting logic
	var IS_SPRINTING = Input.is_action_pressed("Shift") 
	if IS_SPRINTING:
		SPRINT_TIME_ACUMMALTED += delta
		CAMERA.fov = lerp(CAMERA.fov, SPRINT_FOV, FOV_TRANSITION_SPEED * delta)
		if SPRINT_TIME_ACUMMALTED >= 35.0:
			SPRINT_TIME_ACUMMALTED = 0.0
			CAMERA.fov = lerp(CAMERA.fov, SPRINT_FOV, FOV_TRANSITION_SPEED * delta)
	else:
		SPRINT_TIME_ACUMMALTED = 0.0
		CAMERA.fov = lerp(CAMERA.fov, NORMAL_FOV, FOV_TRANSITION_SPEED * delta)
	
	# Crouching logic
	IS_CROUCHING = Input.is_action_pressed("Crouch") and is_on_floor()
	
	# Smooth transition for crouch height
	if IS_CROUCHING:
		scale.y = lerp(scale.y, CROUCH_HEIGHT, CROUCH_TRANSITION_SPEED * delta)
		CAMERA.fov = lerp(CAMERA.fov, CROUCH_FOV, FOV_TRANSITION_SPEED * delta)
		CROUCH_TIME_ACUMMALTED += delta
		if CROUCH_TIME_ACUMMALTED >= 35.0:
			CROUCH_TIME_ACUMMALTED = 0.0
	else:
		CAMERA.fov = lerp(CAMERA.fov, NORMAL_FOV, FOV_TRANSITION_SPEED * delta)
		scale.y = lerp(scale.y, NORMAL_HEIGHT, CROUCH_TRANSITION_SPEED * delta)
		CROUCH_TIME_ACUMMALTED = 0.0
	
	# Sliding logic
	var SHOULD_SLIDE = Input.is_action_pressed("Slide") and is_on_floor()
	var INPUT_DIRECTION := Input.get_vector("Left", "Right", "Forward", "Backward")
	var DIRECTION = (NECK.transform.basis * Vector3(INPUT_DIRECTION.x, 0, INPUT_DIRECTION.y)).normalized()

	if SHOULD_SLIDE and not IS_SLIDING:
		IS_SLIDING = true
		SLIDE_TIMER = SLIDE_DURATION
		SLIDE_DIRECTION = NECK.transform.basis.z.normalized() * -1

	if IS_SLIDING:
		if Input.is_action_pressed("ui_accept"):
			IS_SLIDING = false
			SLIDE_TIMER = 0.0

		elif SLIDE_TIMER > 0:
			SLIDE_TIMER -= delta
			var time_fraction = max(SLIDE_TIMER / SLIDE_DURATION, 0)
			var CURRENT_SLIDE_SPEED = lerp(SLIDE_SPEED * 0.5, SLIDE_SPEED, time_fraction)
			scale.y = lerp(SLIDE_HEIGHT, NORMAL_HEIGHT, time_fraction)
			velocity.x = SLIDE_DIRECTION.x * CURRENT_SLIDE_SPEED
			velocity.z = SLIDE_DIRECTION.z * CURRENT_SLIDE_SPEED
			velocity.x *= (1 - SLIDE_FRICTION)
			velocity.z *= (1 - SLIDE_FRICTION)
			if SLIDE_TIMER <= 0:
				IS_SLIDING = false
		else:
			IS_SLIDING = false
	else:
		if DIRECTION:
			if IS_CROUCHING:
				DEFAULT_SPEED = CROUCH_SPEED
			else:
				DEFAULT_SPEED = 5.0
			if IS_SPRINTING:
				DEFAULT_SPEED *= SPRINT_MULTIPLIER
			else:
				DEFAULT_SPEED = 5.0

			velocity.x = DIRECTION.x * DEFAULT_SPEED
			velocity.z = DIRECTION.z * DEFAULT_SPEED
		else:
			velocity.x = move_toward(velocity.x, 0, DEFAULT_SPEED)
			velocity.z = move_toward(velocity.z, 0, DEFAULT_SPEED)
			
	CAMERA.rotation.x = clamp(CAMERA.rotation.x, deg_to_rad(-40), deg_to_rad(60))

	

	
func _handle_cameras_rotation(_delta: float) -> void:
	CAMERA.rotation.x = clamp(CAMERA.rotation.x, deg_to_rad(-40), deg_to_rad(60))


func can_wallrun(delta):
# Reset gravity and camera properties when not wall running
	gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
	CAMERA.fov = lerp(CAMERA.fov, NORMAL_FOV, FOV_TRANSITION_SPEED * delta)


	if wall_run_right.is_colliding():
		currently_wallrunning = true
		gravity = gravity * 0.5
		velocity * 1.3
		CAMERA.fov = lerp(CAMERA.fov, 110.0, FOV_TRANSITION_SPEED * delta)
		
		CAMERA.rotation_degrees = Vector3(0, 45.0, 0)
	if wall_run_left.is_colliding():
		currently_wallrunning = true
		gravity = gravity * 0.5
		velocity * 1.3
		CAMERA.fov = lerp(CAMERA.fov, 110.0, FOV_TRANSITION_SPEED * delta)
		CAMERA.rotation_degrees = Vector3(0, -45, 0)  # Rotate camera to the left
	else:
		# Reset gravity and camera properties when not wall running
		gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
		if currently_wallrunning:
			return_to_normal_rotation()
			
			#what i think we should create next is double jump 

func return_to_normal_rotation():
	currently_wallrunning = false
	CAMERA.rotation_degrees = Vector3.ZERO
