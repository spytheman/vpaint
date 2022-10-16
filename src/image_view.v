module main

import stbi
import gx
import iui as ui
import gg
import os

[heap]
struct ImageViewData {
mut:
	file      stbi.Image
	id        int
	file_size string
}

pub fn make_image_view(file string, mut win ui.Window, mut app App) &ui.VBox {
	mut vbox := ui.vbox(win)

	mut png_file := stbi.load(file) or { return vbox }
	mut data := &ImageViewData{
		file: png_file
	}
	app.data = data

	mut img := image_from_data(data)
	img.app = app
	app.canvas = img
	vbox.add_child(img)

	file_size := format_size(os.file_size(file))
	data.file_size = file_size

	vbox.set_pos(24, 24)
	/*
	vbox.draw_event_fn = fn mut vbox, img (win voidptr, com &ui.Component) {
		// I prefer extra padding
		padding := int(img.zoom) + 10
		vbox.width = img.width + padding
		vbox.height = img.height + padding
		vbox.overflow = false
	}*/

	return vbox
}

fn (mut img Image) set_zoom(mult f32) {
	img.width = int(img.w * mult)
	img.height = int(img.h * mult)
	img.zoom = mult
}

fn (mut img Image) get_zoom() f32 {
	return img.zoom
}

fn format_size(val f64) string {
	by := f64(1024)

	kb := val / by
	str := '$kb'.str()[0..4]

	if kb > 1024 {
		mb := kb / by
		str2 := '$mb'.str()[0..4]

		return '$str KB / $str2 MB'
	}
	return '$str KB'
}

fn make_gg_image(mut storage ImageViewData, mut win ui.Window, first bool) {
	if first {
		storage.id = win.gg.new_streaming_image(storage.file.width, storage.file.height,
			4, gg.StreamingImageConfig{
			pixel_format: .rgba8
			mag_filter: .nearest
		})
	}
	win.gg.update_pixel_data(storage.id, storage.file.data)
}

// Write as PNG
pub fn write_img(img stbi.Image, path string) {
	stbi.stbi_write_png(path, img.width, img.height, 4, img.data, img.width * 4) or { panic(err) }
}

// Write as JPG
pub fn write_jpg(img stbi.Image, path string) {
	stbi.stbi_write_jpg(path, img.width, img.height, 4, img.data, 80) or { panic(err) }
}

// Get RGB value from image loaded with STBI
pub fn get_pixel(x int, y int, this stbi.Image) gx.Color {
	if x == -1 || y == -1 {
		return gx.rgba(0, 0, 0, 0)
	}

	x_oob := x < 0 || x >= this.width
	y_oob := y < 0 || y >= this.height
	if x_oob || y_oob {
		return gx.rgba(0, 0, 0, -1)
	}

	image := this
	unsafe {
		data := &u8(image.data)
		p := data + (4 * (y * image.width + x))
		r := p[0]
		g := p[1]
		b := p[2]
		a := p[3]
		return gx.Color{r, g, b, a}
	}
}

fn mix_color(ca gx.Color, cb gx.Color) gx.Color {
	if cb.a < 0 {
		return ca
	}

	ratio := f32(1) / 2
	mut r := u8(0)
	mut g := u8(0)
	mut b := u8(0)
	mut a := u8(0)
	for color in [ca, cb] {
		r += u8(color.r * ratio)
		g += u8(color.g * ratio)
		b += u8(color.b * ratio)
		a += u8(color.a * ratio)
	}
	return gx.rgba(r, g, b, a)
}

fn (mut this Image) set(x int, y int, color gx.Color) bool {
	return set_pixel(this.data.file, x, y, color)
}

fn (mut this Image) get(x int, y int) gx.Color {
	return get_pixel(x, y, this.data.file)
}

fn (mut this Image) refresh() {
	mut data := this.data
	refresh_img(mut data, mut this.app.win.gg)
}

// Get RGB value from image loaded with STBI
fn set_pixel(image stbi.Image, x int, y int, color gx.Color) bool {
	if x < 0 || x >= image.width {
		dump(x)
		return false
	}

	if y < 0 || y >= image.height {
		return false
	}

	unsafe {
		data := &u8(image.data)
		p := data + (4 * (y * image.width + x))
		p[0] = color.r
		p[1] = color.g
		p[2] = color.b
		p[3] = color.a
		return true
	}
}

// IMAGE

// Image - implements Component interface
pub struct Image {
	ui.Component_A
pub mut:
	app    &App
	data   &ImageViewData
	w      int
	h      int
	sx     f32
	sy     f32
	mx     int
	my     int
	img    int
	zoom   f32
	loaded bool
}

pub fn image_from_data(data &ImageViewData) &Image {
	return &Image{
		app: 0
		data: data
		img: data.id
		w: data.file.width
		h: data.file.height
		width: data.file.width
		height: data.file.height
		zoom: 1
	}
}

// Load image on first drawn frame
pub fn (mut this Image) load_if_not_loaded(ctx &ui.GraphicsContext) {
	mut win := ctx.win

	make_gg_image(mut this.data, mut win, true)
	this.img = this.data.id
	canvas_height := this.app.sv.height // - (this.app.sv.height / 4)
	zoom_fit := canvas_height / this.data.file.height
	if zoom_fit > 1 {
		this.set_zoom(zoom_fit - 1)
	}
	this.loaded = true
}

pub fn (mut this Image) draw(ctx &ui.GraphicsContext) {
	if !this.loaded {
		this.load_if_not_loaded(ctx)
	}

	ctx.gg.draw_image_with_config(gg.DrawImageConfig{
		img_id: this.img
		img_rect: gg.Rect{
			x: this.x
			y: this.y
			width: this.width
			height: this.height
		}
	})

	color := ctx.theme.text_color
	ctx.gg.draw_rect_empty(this.x, this.y, this.width, this.height, color)

	// Find mouse location data
	this.calculate_mouse_pixel(ctx)

	// Tools
	mut tool := this.app.tool
	tool.draw_hover_fn(this, ctx)

	if this.is_mouse_down {
		tool.draw_down_fn(this, ctx)
	}

	if this.is_mouse_rele {
		tool.draw_click_fn(this, ctx)
		this.is_mouse_rele = false
	}
}

// Updates which pixel the mouse is located
pub fn (mut this Image) calculate_mouse_pixel(ctx &ui.GraphicsContext) {
	mx := ctx.win.mouse_x
	my := ctx.win.mouse_y

	// Simple Editing
	for x in 0 .. this.w {
		for y in 0 .. this.h {
			sx := this.x + (x * this.zoom)
			ex := sx + this.zoom

			sy := this.y + (y * this.zoom)
			ey := sy + this.zoom

			if mx >= sx && mx < ex {
				if my >= sy && my < ey {
					this.sx = sx
					this.sy = sy
					this.mx = x
					this.my = y

					break
				}
			}
		}
	}
}

fn (this &Image) get_point_screen_pos(x int, y int) (f32, f32) {
	sx := this.x + (x * this.zoom)
	sy := this.y + (y * this.zoom)
	return sx, sy
}

fn refresh_img(mut storage ImageViewData, mut ctx gg.Context) {
	ctx.update_pixel_data(storage.id, storage.file.data)
}