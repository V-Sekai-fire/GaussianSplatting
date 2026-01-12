extends GLTFDocumentExtension
class_name GaussianSplattingExtension

const EXTENSION_NAME: String = "KHR_gaussian_splatting"

var gaussian_meshes_cache: Array[int] = []
var gaussian_data_cache: Dictionary = {}

func _get_supported_extensions() -> PackedStringArray:
	print("\n[EXTENSION] _get_supported_extensions called - returning: ", [EXTENSION_NAME])
	return [EXTENSION_NAME]

func _import_preflight(state: GLTFState, extensions_used: PackedStringArray) -> Error:
	print("\n=== _import_preflight called ===")
	print("Extensions used: ", extensions_used)
	
	if extensions_used.has(EXTENSION_NAME):
		print("[PREFLIGHT] Found KHR_gaussian_splatting extension")
		# Initialize class variables
		gaussian_meshes_cache = []
		gaussian_data_cache = {}
		
		# Collect meshes with Gaussian primitives
		gaussian_meshes_cache = []
		var meshes: Array = state.json.get("meshes", [])
		print("[PREFLIGHT] Total meshes in glTF: ", meshes.size())
		
		for mesh_index: int in range(meshes.size()):
			var mesh: Dictionary = meshes[mesh_index]
			for primitive: Dictionary in mesh.get("primitives", []):
				if primitive.get("extensions", {}).has(EXTENSION_NAME):
					gaussian_meshes_cache.append(mesh_index)
					print("[PREFLIGHT] Found Gaussian splat primitive in mesh ", mesh_index)
					break
		
		print("[PREFLIGHT] Cached Gaussian meshes: ", gaussian_meshes_cache)
		state.set_additional_data("gaussian_meshes", gaussian_meshes_cache)
	else:
		print("[PREFLIGHT] KHR_gaussian_splatting NOT in extensions")
	
	return OK

func _import_node(state: GLTFState, gltf_node: GLTFNode, json: Dictionary, parent_node: Node) -> Error:
	print("\n=== _import_node called ===")
	print("[IMPORT_NODE] gaussian_meshes_cache size: ", gaussian_meshes_cache.size())
	print("[IMPORT_NODE] Node name: ", json.get("name", gltf_node.resource_name))

	if json.has("mesh"):
		var mesh_index: int = int(json["mesh"])
		print("[IMPORT_NODE] Node has mesh index: ", mesh_index)
		print("[IMPORT_NODE] Is in gaussian_meshes_cache? ", mesh_index in gaussian_meshes_cache)

		if mesh_index in gaussian_meshes_cache:
			print("[IMPORT_NODE] ✓ This node uses a Gaussian splat mesh")
			# Note: Material will be applied in _generate_scene_node, not here
			return OK
		else:
			print("[IMPORT_NODE] Mesh index NOT in Gaussian cache")
	else:
		print("[IMPORT_NODE] Node has NO mesh attribute")

	return OK

func _generate_scene_node(state: GLTFState, gltf_node: GLTFNode, parent_node: Node) -> Node3D:
	print("\n=== _generate_scene_node called ===")
	print("[GEN_SCENE] gltf_node.mesh index: ", gltf_node.mesh)
	print("[GEN_SCENE] Is in gaussian_meshes_cache? ", gltf_node.mesh in gaussian_meshes_cache)

	if gltf_node.mesh >= 0 and gltf_node.mesh in gaussian_meshes_cache:
		print("[GEN_SCENE] ✓ INTERCEPTING: This is a Gaussian splat node!")

		# Create the MeshInstance3D
		var mesh_instance = MeshInstance3D.new()
		print("[GEN_SCENE] Created MeshInstance3D")

		# Get the mesh from the GLTFMesh
		var gltf_mesh: GLTFMesh = state.meshes[gltf_node.mesh]
		print("[GEN_SCENE] Retrieved GLTFMesh")

		var import_mesh = gltf_mesh.get_mesh()
		print("[GEN_SCENE] Got mesh: ", import_mesh)
		print("[GEN_SCENE] Mesh surface count: ", import_mesh.get_surface_count() if import_mesh else "null")

		if import_mesh:
			# Create shader material BEFORE assigning mesh
			var shader_path: String = "res://addons/gaussian_splats/core/gaussian_splat.gdshader"
			print("[GEN_SCENE] Shader path: ", shader_path)
			
			var shader: Shader = load(shader_path)
			print("[GEN_SCENE] Loaded shader: ", shader)
			
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = shader
			material.resource_local_to_scene = true
			print("[GEN_SCENE] Created ShaderMaterial: ", material)
			print("[GEN_SCENE] Material type: ", material.get_class())
			
			# Set material on the mesh surface BEFORE assigning to MeshInstance3D
			if import_mesh.get_surface_count() > 0:
				import_mesh.set_surface_material(0, material)
				print("[GEN_SCENE] ✓ Set ShaderMaterial on mesh surface 0")
			else:
				print("[GEN_SCENE] ERROR: Mesh has no surfaces!")
			
			mesh_instance.mesh = import_mesh
			print("[GEN_SCENE] ✓ Assigned mesh to MeshInstance3D")
			
			# Don't check surface overrides immediately - let Godot initialize surfaces first
			print("[GEN_SCENE] Skipping immediate surface override check")
			
			print("[GEN_SCENE] ✓ RETURNING custom mesh_instance")
			return mesh_instance
		else:
			print("[GEN_SCENE] ERROR: import_mesh is null!")

		return mesh_instance
	else:
		print("[GEN_SCENE] ✗ NOT a Gaussian splat (mesh not in cache), returning null for default handling")

	# Not a Gaussian splat node, let default handling take over
	return null

func _import_mesh(state: GLTFState, json: Dictionary, extensions: Dictionary, index: int):
	if extensions.has(EXTENSION_NAME):
		var mesh: Mesh = Mesh.new()
		return mesh
	return null

func _import_primitive(state: GLTFState, json: Dictionary, extensions: Dictionary, mesh_index: int, primitive_index: int):
	if extensions.has(EXTENSION_NAME):
		if not gaussian_data_cache.has(mesh_index):
			gaussian_data_cache[mesh_index] = {
				"positions": PackedVector3Array(),
				"scales": PackedVector3Array(),
				"rotations": [],
				"opacities": PackedFloat32Array(),
				"sh_coefficients": [],
				"kernel": "ellipse",
				"color_space": "srgb_rec709_display",
				"sorting_method": "cameraDistance",
				"projection": "perspective"
			}
		
		var data: Dictionary = gaussian_data_cache[mesh_index]
		var ext_data: Dictionary = extensions[EXTENSION_NAME]
		
		# Extract attributes
		var attributes: Dictionary = json.get("attributes", {})
		
		var position_accessor: int = attributes.get("POSITION", -1)
		var scale_accessor: int = attributes.get("KHR_gaussian_splatting:SCALE", -1)
		var rotation_accessor: int = attributes.get("KHR_gaussian_splatting:ROTATION", -1)
		var opacity_accessor: int = attributes.get("KHR_gaussian_splatting:OPACITY", -1)
		
		# Spherical harmonics
		var sh_degrees: Array = []
		for deg: int in range(4):
			var coefs: Array[int] = []
			for n: int in range(2 * deg + 1):
				var attr: String = "KHR_gaussian_splatting:SH_DEGREE_%d_COEF_%d" % [deg, n]
				var acc: int = attributes.get(attr, -1)
				if acc != -1:
					coefs.append(acc)
				else:
					break
			if coefs.size() == 2 * deg + 1:
				sh_degrees.append(coefs)
			else:
				break
		
		# Extract data from accessors
		var positions: PackedVector3Array = PackedVector3Array(extract_accessor_data(state, position_accessor, "VEC3"))
		var scales: PackedVector3Array = PackedVector3Array(extract_accessor_data(state, scale_accessor, "VEC3"))
		var rotations_data: Array = extract_accessor_data(state, rotation_accessor, "VEC4")
		var rotations: Array[Quaternion] = []
		for r: Variant in rotations_data:
			rotations.append(Quaternion(r.x, r.y, r.z, r.w))
		var opacities: PackedFloat32Array = PackedFloat32Array(extract_accessor_data(state, opacity_accessor, "SCALAR"))
		
		var sh_coefficients: Array = []
		for deg_coefs: Array in sh_degrees:
			var deg_data: Array[PackedVector3Array] = []
			for acc: int in deg_coefs:
				deg_data.append(PackedVector3Array(extract_accessor_data(state, acc, "VEC3")))
			sh_coefficients.append(deg_data)
		
		# Append to mesh data
		data["positions"].append_array(positions)
		data["scales"].append_array(scales)
		data["rotations"].append_array(rotations)
		data["opacities"].append_array(opacities)
		# For SH, assume same structure, append
		if data["sh_coefficients"].is_empty():
			data["sh_coefficients"] = sh_coefficients
		else:
			for deg: int in range(sh_coefficients.size()):
				if deg < data["sh_coefficients"].size():
					for n: int in range(sh_coefficients[deg].size()):
						if n < data["sh_coefficients"][deg].size():
							data["sh_coefficients"][deg][n].append_array(sh_coefficients[deg][n])
		
		# Update ext_data if not set
		if data["kernel"] == "ellipse":
			data["kernel"] = ext_data.get("kernel", "ellipse")
			data["color_space"] = ext_data.get("colorSpace", "srgb_rec709_display")
			data["sorting_method"] = ext_data.get("sortingMethod", "cameraDistance")
			data["projection"] = ext_data.get("projection", "perspective")
		
		print("GaussianSplattingExtension: Extracted Gaussian data for mesh ", mesh_index, " primitive ", primitive_index, ": ", positions.size(), " splats")
	# Return null
	return null

func extract_accessor_data(state: GLTFState, accessor_index: int, type: String) -> Array:
	if accessor_index == -1:
		return []
	
	var accessor: GLTFAccessor = state.accessors[accessor_index]
	var buffer_view: GLTFBufferView = state.buffer_views[accessor.buffer_view]
	var buffer: PackedByteArray = state.buffers[buffer_view.buffer]
	
	var data: PackedByteArray = buffer
	var offset: int = buffer_view.byte_offset + accessor.byte_offset
	var count: int = accessor.count
	var component_type: int = accessor.component_type
	var component_size: int = get_component_type_size(component_type)
	var num_components: int = get_type_components(type)
	var stride: int = buffer_view.byte_stride if buffer_view.byte_stride > 0 else component_size * num_components
	
	var result: Array = []
	for i: int in range(count):
		var vec: Array[float] = []
		for c: int in range(num_components):
			var value: float = 0
			if component_type == 5126:  # FLOAT
				value = data.decode_float(offset + i * stride + c * 4)
			elif component_type == 5121:  # UNSIGNED_BYTE
				value = data[offset + i * stride + c]
				if accessor.normalized:
					value /= 255.0
			elif component_type == 5123:  # UNSIGNED_SHORT
				value = data.decode_u16(offset + i * stride + c * 2)
				if accessor.normalized:
					value /= 65535.0
			elif component_type == 5120:  # SIGNED_BYTE
				value = data.decode_s8(offset + i * stride + c)
				if accessor.normalized:
					value = (value + 128) / 255.0 * 2 - 1
			elif component_type == 5122:  # SIGNED_SHORT
				value = data.decode_s16(offset + i * stride + c * 2)
				if accessor.normalized:
					value = (value + 32768) / 65535.0 * 2 - 1
			vec.append(value)
		
		if type == "SCALAR":
			result.append(vec[0])
		elif type == "VEC3":
			result.append(Vector3(vec[0], vec[1], vec[2]))
		elif type == "VEC4":
			result.append(Quaternion(vec[0], vec[1], vec[2], vec[3]))  # Assuming quaternion
	
	return result

func get_component_type_size(component_type: int) -> int:
	match component_type:
		5120, 5121:  # SIGNED_BYTE, UNSIGNED_BYTE
			return 1
		5122, 5123:  # SIGNED_SHORT, UNSIGNED_SHORT
			return 2
		5126:  # FLOAT
			return 4
		_:
			return 0

func get_type_components(type: String) -> int:
	match type:
		"SCALAR":
			return 1
		"VEC2":
			return 2
		"VEC3":
			return 3
		"VEC4":
			return 4
		_:
			return 0

func create_quad_mesh(data, i) -> ImporterMesh:
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(2, 2)
	var arrays: Array = plane.surface_get_arrays(0)
	var mesh: ImporterMesh = ImporterMesh.new()
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://addons/gaussian_splats/core/gaussian_splat.gdshader")
	material.set_shader_parameter("scale", data["scales"][i])
	material.set_shader_parameter("opacity", data["opacities"][i])
	var sh: Vector3 = data["sh_coefficients"][0][0][i] if data["sh_coefficients"].size() > 0 and data["sh_coefficients"][0].size() > 0 and data["sh_coefficients"][0][0].size() > i else Vector3(1,1,1)
	material.set_shader_parameter("sh_0", sh)	
	var actual_scale: Vector3 = Vector3(exp(data["scales"][i].x), exp(data["scales"][i].y), exp(data["scales"][i].z))
	var max_scale_val: float = max(actual_scale.x, max(actual_scale.y, actual_scale.z))
	material.set_shader_parameter("max_scale", max_scale_val)
	material.resource_local_to_scene = true
	mesh.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, material)
	return mesh
