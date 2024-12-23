extends Node

@onready var code_edit = $CodeEdit
@onready var run_button = $Button
@onready var output_label = $Panel2/RichTextLabel
@onready var task_label = $Panel/TaskLabel
@onready var score_label = $ScoreLabel
@onready var canvas_layer = get_parent()
var python_thread: Thread
var _mutex: Mutex
var _output: String = ""
var editor_focused: bool = false

# Challenge system signals
signal challenge_completed
signal challenge_failed
signal all_challenges_completed

# List of all challenges
var challenges = [
	{
		"prompt": """# Question: Create two variables, one containing the number 11 and another 
# containing the string 'Python', then print them on separate lines.
#
# Expected Output:
# 11
# Python

""",
		"expected_output": "11\nPython",
		"description": "Task 1: Variables - Create and print two variables. Use the number 11 and 'Python'"
	},
	{
	"prompt": """# Question: Write code using an if statement and proper indentation.
# Use this exact structure but fill in your own condition:
# if condition:
#     print("This line is indented!")
#
# Expected Output:
# This line is indented!

""",
	"expected_output": "This line is indented!",
	"description": "Task 2: Indentation - Write an if statement with proper indentation and \nprint ('This line is indented!')"
},
	{
		"prompt": """# Question: Create three variables with:
# - A number with value 5
# - A decimal with value 2.5
# - A text with value "Hello"
# Then print them each on a new line.
#
# Expected Output:
# 5
# 2.5
# Hello

""",
		"expected_output": "5\n2.5\nHello",
		"description": "Task 3: Data Types - Create and print different types of variables. \nUse number 5 for int, 2.5 for float and 'Hello' for string."
	},
	{
		"prompt": """# Question: Create a program that checks if someone can vote.
# If age is 18 or higher, print "Can vote", otherwise print "Cannot vote".
# Use age 16 for testing.
#
# Expected Output:
# Cannot vote

""",
		"expected_output": "Cannot vote",
		"description": "Task 4: If-Else - Create a voting age checker. If age is 18 or higher, print 'Can vote', \notherwise print 'Cannot vote'. Use age 16 for testing"
	},
	{
		"prompt": """# Question: Create a program that tells if a number is positive,
# negative, or zero. Test with number 5.
#
# Expected Output:
# Positive

""",
		"expected_output": "Positive",
		"description": "Task 5: Elif Statement - Check if a number is positive, negative, or zero. Test with number 5"
	}
]

# Challenge tracking
var current_challenge_index = 0
var current_challenge = null
var correct_answers = 0
var incorrect_answers = 0
var active_notification: Panel = null

func _ready():
	run_button.pressed.connect(_on_run_button_pressed)
	_mutex = Mutex.new()
	python_thread = Thread.new()
	setup_syntax_highlighting()
	setup_theme()
	setup_minimap()
	setup_indent_guides()
	setup_task_label()
	setup_score_label()
	
	# Start first challenge
	start_challenge(0)

func setup_score_label():
	# Create score label if it doesn't exist
	if !has_node("ScoreLabel"):
		var label = Label.new()
		label.name = "ScoreLabel"
		add_child(label)
		score_label = label
	
	# Style the score label
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color("FFFFFF"))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Position it in the top-right corner
	score_label.size = Vector2(200, 30)
	score_label.position = Vector2(get_viewport().size.x - 1310, 5)
	
	update_score_display()

func update_score_display():
	score_label.text = "Score: %d/%d (Correct: %d)" % [correct_answers, challenges.size(), correct_answers]

func setup_task_label():
	# Create a label for the task if it doesn't exist
	if !$Panel.has_node("TaskLabel"):
		var label = Label.new()
		label.name = "TaskLabel"
		$Panel.add_child(label)
		task_label = label
	
	# Style the task label
	task_label.add_theme_font_size_override("font_size", 16)
	task_label.add_theme_color_override("font_color", Color("FFFFFF"))
	task_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	task_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	task_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)

func validate_code_structure(code: String, challenge_index: int) -> bool:
	match challenge_index:
		0:  # Variables task
			var variable_count = 0
			var print_count = 0
			var lines = code.split("\n")
			
			for line in lines:
				line = line.strip_edges()
				if line.contains("="):  # Count variable assignments
					variable_count += 1
				if line.contains("print"):
					print_count += 1
			
			# Require exactly 2 variables and 2 print statements
			return variable_count == 2 and print_count == 2
			
		1:  # Indentation task
			print("Indentation Check:")
			var lines = Array(code.split("\n"))
			var found_if = false
			var found_indented_print = false
			
			for i in range(lines.size()):
				var line = lines[i].strip_edges(true, true)  # Remove trailing whitespace
				print("Line %d: '%s'" % [i, lines[i]])  # Debug complete line
				
				if line.begins_with("if "):
					found_if = true
					continue
					
				if found_if:
					# Check the raw line for either tab or spaces at start
					var raw_line = lines[i]
					if (raw_line.begins_with("\t") or raw_line.begins_with("    ")) and raw_line.contains("print"):
						found_indented_print = true
						break
			
			print("Found if: %s, Found indent: %s" % [found_if, found_indented_print])
			return found_if and found_indented_print
			
		2:  # Multiple variables/data types task
			var has_number = false
			var has_decimal = false
			var has_string = false
			var has_print = false
			
			for line in code.split("\n"):
				line = line.strip_edges()
				if line.contains("="):
					if line.contains("\"") or line.contains("'"):  # String check
						has_string = true
					elif line.contains("."):  # Decimal check
						has_decimal = true
					elif line.match("*=*[0-9]*"):  # Number check
						has_number = true
				if line.contains("print"):
					has_print = true
					
			return has_print and (has_number or has_decimal) and has_string
			
		3:  # If-else task
			var has_if = false
			var has_else = false
			var lines = code.split("\n")
			
			for line in lines:
				line = line.strip_edges()
				if line.begins_with("if "):
					has_if = true
				elif line.strip_edges() == "else:":
					has_else = true
					
			return has_if and has_else
			
		4:  # Elif task
			var has_if = false
			var has_elif = false
			var lines = code.split("\n")
			
			for line in lines:
				line = line.strip_edges()
				if line.begins_with("if "):
					has_if = true
				elif line.begins_with("elif "):
					has_elif = true
					
			return has_if and has_elif
			
	return false

func get_validation_error(challenge_index: int) -> String:
	match challenge_index:
		0:
			return "You must create exactly TWO variables and print them both!"
		1:
			return "Your code must use proper indentation with if statement!"
		2:
			return "Your code must use different data types (number, decimal, string)!"
		3:
			return "Your code must use both if and else statements!"
		4:
			return "Your code must use both if and elif statements!"
	return "Invalid code structure!"

func create_notification(success: bool, message: String):
	# Remove existing notification if present
	if active_notification != null:
		active_notification.queue_free()
	
	# Create notification panel
	var notification = Panel.new()
	add_child(notification)
	active_notification = notification
	
	# Style the panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("1E1E1E")
	panel_style.border_width_left = 4
	panel_style.border_color = Color("22C55E") if success else Color("EF4444")
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	notification.add_theme_stylebox_override("panel", panel_style)
	
	# Create container for content
	var container = HBoxContainer.new()
	notification.add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 10)
	
	# Create icon label
	var icon = Label.new()
	container.add_child(icon)
	icon.text = "✓" if success else "✗"
	icon.add_theme_font_size_override("font_size", 20)
	icon.add_theme_color_override("font_color", Color("22C55E") if success else Color("EF4444"))
	
	# Add spacing
	var spacer = Control.new()
	container.add_child(spacer)
	spacer.custom_minimum_size.x = 10
	
	# Create message label
	var label = Label.new()
	container.add_child(label)
	label.text = message
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_color", Color("FFFFFF"))
	
	# Position the notification
	notification.size = Vector2(300, 80)
	notification.position = Vector2(get_viewport().size.x - notification.size.x - 20, -100)
	
	# Create animation
	var tween = create_tween()
	tween.set_parallel(false)
	
	# Slide down
	tween.tween_property(notification, "position:y", 20, 0.5)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_OUT)
	
	# Wait
	tween.tween_interval(2.0)
	
	# Slide up and free
	tween.tween_property(notification, "position:y", -100, 0.5)\
		.set_trans(Tween.TRANS_BACK)\
		.set_ease(Tween.EASE_IN)
	tween.tween_callback(notification.queue_free)
	tween.tween_callback(func(): active_notification = null)

func setup_indent_guides():
	code_edit.draw_tabs = true
	code_edit.indent_size = 4
	code_edit.draw_spaces = false
	
	code_edit.add_theme_color_override("indent_guide_color", Color("404040"))
	code_edit.add_theme_constant_override("indent_guide_width", 1)

func setup_minimap():
	code_edit.minimap_draw = true
	code_edit.minimap_width = 60
	
	code_edit.add_theme_color_override("minimap_background", Color("1E1E1E"))
	code_edit.add_theme_color_override("minimap_selection_color", Color(0.247, 0.431, 0.705, 0.5))

func setup_theme():
	# Top button styling
	run_button.text = "RUN"
	run_button.custom_minimum_size = Vector2(70, 28)
	run_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	run_button.add_theme_font_size_override("font_size", 12)
	var button_style = StyleBoxFlat.new()
	button_style.bg_color = Color("2F3239")
	button_style.border_color = Color("404040")
	button_style.border_width_left = 1
	button_style.border_width_right = 1
	button_style.border_width_top = 1
	button_style.border_width_bottom = 1
	button_style.corner_radius_top_left = 3
	button_style.corner_radius_top_right = 3
	button_style.corner_radius_bottom_left = 3
	button_style.corner_radius_bottom_right = 3
	run_button.add_theme_stylebox_override("normal", button_style)
	run_button.add_theme_color_override("font_color", Color("CCCCCC"))
	
	# Panel Node styling
	var panel = $Panel
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("1E1E1E")
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# Output panel styling
	var output_panel = $Panel2
	var output_style = StyleBoxFlat.new()
	output_style.bg_color = Color("1E1E1E")
	output_panel.add_theme_stylebox_override("panel", output_style)
	
	# Separator styling
	for child in get_children():
		if child is HSeparator:
			child.add_theme_constant_override("separation", 1)
			child.add_theme_color_override("color", Color("404040"))
	
	# Output text styling
	output_label.add_theme_color_override("default_color", Color("CCCCCC"))
	output_label.add_theme_font_size_override("normal_font_size", 16)
	output_label.add_theme_font_size_override("bold_font_size", 16)
	output_label.add_theme_font_size_override("italics_font_size", 16)
	output_label.add_theme_font_size_override("mono_font_size", 16)
	output_label.add_theme_color_override("font_outline_color", Color.BLACK)
	output_label.add_theme_constant_override("outline_size", 1)

func setup_syntax_highlighting():
	code_edit.add_theme_color_override("background_color", Color("1E1E1E"))
	code_edit.add_theme_color_override("font_color", Color("D4D4D4"))
	code_edit.add_theme_color_override("current_line_color", Color("282828"))
	
	var highlighter = CodeHighlighter.new()
	code_edit.syntax_highlighter = highlighter
	
	highlighter.number_color = Color("B5CEA8")
	highlighter.symbol_color = Color("D4D4D4")
	highlighter.function_color = Color("DCDCAA")
	highlighter.member_variable_color = Color("9CDCFE")
	
	var keywords = ["def", "if", "else", "elif", "for", "while", "class", "return", 
				   "import", "from", "True", "False", "None", "and", "or", "not", "is", "in", "range"]
	for keyword in keywords:
		highlighter.add_keyword_color(keyword, Color("C586C0"))
	
	var types = ["int", "str", "float", "bool", "list", "dict", "set", "tuple"]
	for type in types:
		highlighter.add_keyword_color(type, Color("4EC9B0"))
	
	var functions = ["print", "len", "range", "sum", "min", "max", "append"]
	for func_name in functions:
		highlighter.add_keyword_color(func_name, Color("DCDCAA"))
	
	highlighter.add_color_region("\"", "\"", Color("CE9178"))
	highlighter.add_color_region("'", "'", Color("CE9178"))
	highlighter.add_color_region("#", "", Color("6A9955"), true)
	
	code_edit.gutters_draw_line_numbers = true
	code_edit.add_theme_color_override("line_number_color", Color("858585"))
	code_edit.add_theme_color_override("caret_color", Color("A6B39B"))
	code_edit.add_theme_color_override("selection_color", Color(0.247, 0.431, 0.705, 0.5))
	
	code_edit.auto_brace_completion_enabled = true
	code_edit.indent_automatic = true
	code_edit.indent_size = 4
	code_edit.draw_tabs = true
	code_edit.draw_spaces = false

func verify_output(output: String):
	# Clean the output string
	var cleaned_output = output.strip_edges()
	cleaned_output = cleaned_output.replace("[color=#98C379]", "").replace("[/color]", "")
	cleaned_output = cleaned_output.replace("[color=#E06C75]", "").replace("[/color]", "")
	cleaned_output = cleaned_output.replace("Code executed successfully with no output", "")
	cleaned_output = cleaned_output.strip_edges()
	
	# Debug prints
	print("\nValidation Debug:")
	print("Expected output: '%s'" % current_challenge.expected_output)
	print("Actual output: '%s'" % cleaned_output)
	print("Code structure valid: %s" % validate_code_structure(code_edit.text, current_challenge_index))
	
	# Normalize line endings
	var expected = current_challenge.expected_output.replace("\n", "\n")
	var actual = cleaned_output.replace("\r\n", "\n")
	
	var output_matches = actual == expected
	var structure_valid = validate_code_structure(code_edit.text, current_challenge_index)
	
	print("Output matches: %s" % output_matches)
	print("Structure valid: %s" % structure_valid)
	
	if output_matches and structure_valid:
		correct_answers += 1
		emit_signal("challenge_completed")
		create_notification(true, "Challenge completed successfully!")
	else:
		incorrect_answers += 1
		emit_signal("challenge_failed")
		if !structure_valid:
			create_notification(false, get_validation_error(current_challenge_index))
		else:
			create_notification(false, "Output doesn't match expected result.")
	
	update_score_display()
	await get_tree().create_timer(1.5).timeout
	next_challenge()

func next_challenge():
	if current_challenge_index + 1 >= challenges.size():
		show_final_result()
	else:
		start_challenge(current_challenge_index + 1)

func show_final_result() -> void:
	var total_challenges := challenges.size()
	var pass_threshold := 4
	
	if correct_answers >= pass_threshold:
		create_notification(true, "Congratulations! You passed with %d/%d correct!" % [correct_answers, total_challenges])

		# Wait for notification then remove the canvas layer
		await get_tree().create_timer(2.0).timeout
		canvas_layer.queue_free()
	else:
		create_notification(false, "You got %d/%d correct. Talk to Shadewalker to try again!" % [correct_answers, total_challenges])
		# Wait for notification
		await get_tree().create_timer(2.0).timeout
		# Hide the canvas layer and reset the quiz
		canvas_layer.hide()
		# Reset the quiz state for next attempt
		await get_tree().create_timer(0.5).timeout
		reset_challenges()

func reset_challenges():
	current_challenge_index = 0
	correct_answers = 0
	incorrect_answers = 0
	update_score_display()
	start_challenge(0)

func start_challenge(index: int):
	current_challenge_index = index
	current_challenge = challenges[index]
	
	# Update UI
	task_label.text = current_challenge.description
	code_edit.text = current_challenge.prompt
	output_label.text = "" # Clear previous output

func _on_run_button_pressed():
	if python_thread.is_started():
		output_label.text = "Previous code is still running..."
		return
	
	var code = code_edit.text
	output_label.text = "Running..."
	python_thread.start(_execute_python_code.bind(code))

func _execute_python_code(code: String):
	var output = []
	var exit_code = 0
	
	var dir = OS.get_user_data_dir()
	var temp_file_path = dir.path_join("temp_script.py")
	
	var temp_file = FileAccess.open(temp_file_path, FileAccess.WRITE)
	if temp_file:
		temp_file.store_string(code)
		temp_file.close()
	
	var python_path = "python" # or "python3" depending on your system
	var args = [temp_file_path]
	
	var output_array = []
	exit_code = OS.execute(python_path, args, output_array, true)
	
	call_deferred("_update_output", output_array, exit_code)
	
	DirAccess.remove_absolute(temp_file_path)
	
	call_deferred("_thread_done")

func _update_output(output_array: Array, exit_code: int):
	var final_output = ""
	
	if exit_code != 0:
		final_output = "Error executing code (exit code: %d)\n" % exit_code
	
	for line in output_array:
		final_output += line + "\n"
	
	if final_output.is_empty():
		final_output = "Code executed successfully with no output."
	
	output_label.text = final_output
	verify_output(final_output)

func _thread_done():
	python_thread.wait_to_finish()

func _exit_tree():
	if python_thread.is_started():
		python_thread.wait_to_finish()
