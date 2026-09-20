extends RefCounted
## Характеристики машин. Добавляй свои модели сюда.

const TYPES := [
	{
		"name": "Девятка",
		"body": Vector3(1.65, 0.5, 3.9), "cabin": Vector3(1.5, 0.55, 1.7), "cabin_z": 0.35,
		"track": 1.36, "wheelbase": 2.4, "wheel_r": 0.28,
		"max_speed": 28.0, "accel": 13.0,
	},
	{
		"name": "Классика",
		"body": Vector3(1.7, 0.55, 4.3), "cabin": Vector3(1.55, 0.5, 1.8), "cabin_z": 0.3,
		"track": 1.4, "wheelbase": 2.6, "wheel_r": 0.31,
		"max_speed": 26.0, "accel": 11.0,
	},
	{
		"name": "Седан",
		"body": Vector3(1.75, 0.55, 4.6), "cabin": Vector3(1.6, 0.52, 2.0), "cabin_z": 0.15,
		"track": 1.44, "wheelbase": 2.7, "wheel_r": 0.32,
		"max_speed": 31.0, "accel": 14.0,
	},
	{
		"name": "Пикап",
		"body": Vector3(1.8, 0.6, 4.8), "cabin": Vector3(1.65, 0.6, 1.5), "cabin_z": 0.9,
		"track": 1.5, "wheelbase": 2.9, "wheel_r": 0.36,
		"max_speed": 27.0, "accel": 12.0,
	},
	{
		"name": "Маршрутка",
		"body": Vector3(1.95, 1.15, 4.9), "cabin": Vector3(1.9, 0.65, 2.6), "cabin_z": -0.5,
		"track": 1.54, "wheelbase": 3.0, "wheel_r": 0.34,
		"max_speed": 24.0, "accel": 9.0,
	},
]

const PAINTS := [
	Color("e8e8e8"), Color("a33b3b"), Color("33507a"), Color("3f5a3f"),
	Color("c9bc95"), Color("4a3352"), Color("22242a"), Color("d98e2b"),
	Color("7a2f4f"), Color("2e6e6a"), Color("88919c"), Color("5d3a1f"),
]
