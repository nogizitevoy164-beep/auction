extends SceneTree
## Проверка API: умеет ли головной Godot читать SVG напрямую
## (Image.load_svg) и сохранять PNG без импорта редактором.

func _initialize() -> void:
	print("ClassDB Image.load_svg: ", ClassDB.class_has_method("Image", "load_svg", true))
	print("ClassDB Image.save_png: ", ClassDB.class_has_method("Image", "save_png", true))
	print("ClassDB ImageTexture.create_from_image: ",
			ClassDB.class_has_method("ImageTexture", "create_from_image", true))
	print("ClassDB ResourceSaver.save: ", ClassDB.class_has_method("ResourceSaver", "save", true))
	quit(0)
