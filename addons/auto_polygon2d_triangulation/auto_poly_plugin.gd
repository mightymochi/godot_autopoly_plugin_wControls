@tool
extends EditorPlugin

var selected_polygon2d : Polygon2D = null
var previous_points : PackedVector2Array
var _polygon_2d_editor_panels : Array[Panel] = []
var _toolbar_button : Button
var _dock_control : CheckButton
var _dock_container : VBoxContainer
var _dock_button : Button 

func _enter_tree() -> void:
	_polygon_2d_editor_panels = _get_polygon_2d_editor_panels()
	_toolbar_button = Button.new()
	_toolbar_button.hide()
	_toolbar_button.pressed.connect(_on_button_pressed)
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)
	_dock_container = VBoxContainer.new()
	_dock_container.name = "Auto-Triangulate" 
	_dock_control = CheckButton.new()
	_dock_control.text = "Enable Auto-Triangulation"
	_dock_container.add_child(_dock_control)
	_dock_button = Button.new()
	_dock_button.text = "Auto Tri Polygon"
	_dock_button.pressed.connect(_on_button_pressed)
	_dock_container.add_child(_dock_button)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock_container)

func _exit_tree() -> void:
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar_button)
	_toolbar_button.queue_free()
	remove_control_from_docks(_dock_container)
	_dock_container.queue_free()

func _on_button_pressed() -> void:
	if not selected_polygon2d: return
	
	# Toggle logic: If true -> false, If false/missing -> true
	var current_state = selected_polygon2d.get_meta("auto_triangulate", false)
	var next_state = not current_state
	
	# Undo/Redo Management
	var ur = get_undo_redo()
	ur.create_action("Toggle Auto Triangulate")
	ur.add_do_method(selected_polygon2d, "set_meta", "auto_triangulate", next_state)
	ur.add_undo_method(selected_polygon2d, "set_meta", "auto_triangulate", current_state)
	# Refresh UI after undo/redo
	ur.add_do_method(self, "_update_button_ui")
	ur.add_undo_method(self, "_update_button_ui")
	ur.commit_action()

func _update_button_ui() -> void:
	# Reference both buttons in an array to update them at once
	var buttons = [_toolbar_button, _dock_button]
	
	if not selected_polygon2d:
		for b in buttons:
			b.disabled = true # Disable dock button if nothing selected
			b.hide()
		_toolbar_button.hide()
		return
	
	for b in buttons:
		b.show()
		b.disabled = false
		if not selected_polygon2d.has_meta("auto_triangulate"):
			b.text = "AutoT"
			b.modulate = Color.WHITE
		elif selected_polygon2d.get_meta("auto_triangulate"):
			b.text = "AutoT: TRUE"
			b.modulate = Color.GREEN
		else:
			b.text = "AutoT: FALSE"
			b.modulate = Color.CORAL

func _process(_delta: float) -> void:
	if not _dock_control.button_pressed or selected_polygon2d == null or not selected_polygon2d.get_meta("auto_triangulate", false):
		return
	#if selected_polygon2d == null or not selected_polygon2d.get_meta("auto_triangulate", false):
		#return
	if selected_polygon2d.polygon != previous_points:
		triangulate_polygons(selected_polygon2d)
		_queue_redraw_panels(_polygon_2d_editor_panels)
		previous_points = selected_polygon2d.polygon.duplicate()

func _handles(object: Object) -> bool:
	if object is Polygon2D:
		selected_polygon2d = object
		previous_points = selected_polygon2d.polygon.duplicate()
		_update_button_ui()
		return true
	selected_polygon2d = null
	_toolbar_button.hide()
	return false
	
func triangulate_polygons(polygon2d : Polygon2D) -> void:
	if polygon2d.polygon.size() < 3:
		# Can't triangulate without a triangle...
		return

	polygon2d.polygons = []
	var points = Geometry2D.triangulate_delaunay(polygon2d.polygon)
	# Outer verticies are stored at the beginning of the PackedVector2Array
	var outer_polygon = polygon2d.polygon.slice(0, polygon2d.polygon.size() - polygon2d.internal_vertex_count)
	for point in range(0, points.size(), 3):
		var triangle = []
		triangle.push_back(points[point])
		triangle.push_back(points[point + 1])
		triangle.push_back(points[point + 2])
		
		# only add the triangle if all points are inside the polygon
		var a : Vector2 = polygon2d.polygon[points[point]]
		var b : Vector2 = polygon2d.polygon[points[point + 1]]
		var c : Vector2 = polygon2d.polygon[points[point + 2]]
		
		if _points_are_inside_polygon(a, b, c, outer_polygon):
			polygon2d.polygons.push_back(triangle)


# Find the Panels associated with the Polygon2DEditor node.
func _get_polygon_2d_editor_panels() -> Array[Panel] :
	var panels : Array[Panel] = []
	# Find the editor
	for child in get_editor_interface().get_base_control().find_children("*","Polygon2DEditor", true, false):
		# Find the "uv_edit_draw" panel https://github.com/godotengine/godot/blob/2a0aef5f0912b60f85c9e150cc0bfbeab7de6e40/editor/plugins/polygon_2d_editor_plugin.cpp#L1348
		# Note that this finds multiple panels as all of these nodes are nameless..
		panels.append_array(child.find_children("*", "Panel", true, false))
	return panels


func _queue_redraw_panels(panels: Array[Panel]) -> void:
	for panel in panels:
		if panel.is_visible_in_tree():
			panel.queue_redraw()


func _points_are_inside_polygon(a: Vector2, b: Vector2, c: Vector2, polygon: PackedVector2Array) -> bool:
	var center = (a + b + c) / 3
	# move points inside the triangle so we don't check for intersection with polygon edge
	a = a - (a - center).normalized() * 0.01
	b = b - (b - center).normalized() * 0.01
	c = c - (c - center).normalized() * 0.01
	
	return Geometry2D.is_point_in_polygon(a, polygon) \
		and Geometry2D.is_point_in_polygon(b, polygon) \
		and Geometry2D.is_point_in_polygon(c, polygon)
