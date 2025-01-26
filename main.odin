package main

import "jo/app"
import gl "vendor:OpenGL"
import "core:image/png"
import "core:math/linalg"
import "core:fmt"
import "core:os"

Game_Context :: struct {
	vbo, vao: u32,
	shader: u32,

    player: Entity,
    textures: [4]u32,
    img_bubble, img_bubble_pop, img_bubble_respawn, img_spike: ^png.Image,

    level: []byte,
}

Entity_State :: enum {
    Respawn,
    Free,
    Pop,
}

Entity :: struct {
    tick: f64,
    using pos: [2]f32,
    vel: [2]f32,
    frame_idx: i32,
    state: Entity_State,
}

GAME_WIDTH :: 576
GAME_HEIGHT :: 324

BUBBLE_FRAME_WIDTH :: 32
BUBBLE_FRAME_TIME :: 0.1

BUBBLE_FRAME_COUNT :: 6

PLAYER_ACC :: 0.1

Instance :: struct {
    frame_idx, frame_count: i32,
    pos: [2]f32,
}

main :: proc() {
    os.change_directory("build")

	app_ctx: app.Context
	app_ctx.keys[.Escape] += {.Exit}
	using game_ctx: Game_Context
	app_ctx.user_data = &game_ctx
	app.init(&app_ctx)
    major, minor: int
    when ODIN_DEBUG {
        major = 4
        minor = 3
    } else {
        major = 3
        minor = 3
    }
	app.gl_init(&app_ctx, major, minor)

    err: png.Error
	img_bubble, err = png.load("bubble.png")
    assert(err == nil)
    img_bubble_pop, err = png.load("bubble_pop.png")
    assert(err == nil)
    img_bubble_respawn, err = png.load("bubble_respawn.png")
    assert(err == nil)
    img_spike, err = png.load("spike.png")
    assert(err == nil)

    vertices_from_img :: proc(img: ^png.Image, frame_width, frame_count: int) -> (vertices: [6][4]f32) {
        vertices[0] = {0.0, f32(img.height), 0.0, 1.0}
        vertices[1] = {f32(frame_width), 0.0, 1.0/f32(frame_count), 0.0}
        vertices[2] = {0.0, 0.0, 0.0, 0.0}

        vertices[3] = vertices[0]
        vertices[4] = {f32(frame_width), f32(img.height), 1.0/f32(frame_count), 1.0}
        vertices[5] = vertices[1]

        return
    }

    bubble_vertices := vertices_from_img(img_bubble, BUBBLE_FRAME_WIDTH, BUBBLE_FRAME_COUNT)
    // bubble_pop_vertices := vertices_from_img(img_bubble_pop, BUBBLE_FRAME_WIDTH, BUBBLE_POP_FRAME_COUNT)
    // bubble_respawn_vertices := vertices_from_img(img_bubble_respawn, BUBBLE_FRAME_WIDTH, BUBBLE_RESPAWN_FRAME_COUNT)
    spike_vertices := vertices_from_img(img_spike, img_spike.width, 1)

    gl.GenVertexArrays(1, &vao)
    gl.GenBuffers(1, &vbo)

    gl.BindVertexArray(vao)

    gl.BindBuffer(gl.ARRAY_BUFFER, vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(bubble_vertices), raw_data(&bubble_vertices), gl.STATIC_DRAW)

    gl.VertexAttribPointer(0, 4, gl.FLOAT, gl.FALSE, 4 * size_of(f32), {})
    gl.EnableVertexAttribArray(0)

    // load and create a texture 
    // -------------------------
    gl.GenTextures(i32(len(textures)), raw_data(&textures))
    texture_init :: proc(texture: u32, img: ^png.Image) {
        gl.BindTexture(gl.TEXTURE_2D, texture)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST_MIPMAP_NEAREST)
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST)

        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGBA, i32(img.width), i32(img.height), 0, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(img.pixels.buf[:]))
        gl.GenerateMipmap(gl.TEXTURE_2D)
    }
    texture_init(textures[0], img_bubble)
    texture_init(textures[1], img_bubble_pop)
    texture_init(textures[2], img_bubble_respawn)
    texture_init(textures[3], img_spike)

    shader_ok: bool
    shader, shader_ok = gl.load_shaders("shader.vs", "shader.fs")
    assert(shader_ok)
    gl.UseProgram(shader)

    proj := linalg.matrix_ortho3d_f32(0.0, GAME_WIDTH, GAME_HEIGHT, 0, -1, 1)
    gl.UniformMatrix4fv(gl.GetUniformLocation(shader, "proj"), 1, gl.FALSE, &proj[0, 0])

    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    gl.Disable(gl.DEPTH_TEST)

    player.pos = {GAME_WIDTH/2, GAME_HEIGHT/2}

    level_ok: bool
    level, level_ok = os.read_entire_file("level")
    assert(level_ok)

	app.run(&app_ctx, update)

	update :: proc(using app_ctx: ^app.Context, dt: f64) {
		using game_ctx := (^Game_Context)(app_ctx.user_data)

        advance_frame_idx :: proc(using entity: ^Entity, dt, frame_time: f64, frame_count: i32) -> (animation_completed: bool) {
            tick += dt
            if tick > frame_time {
                tick = 0
                frame_idx += 1
                if frame_idx >= frame_count {
                    animation_completed = true
                    frame_idx = 0
                }
            }
            return
        }

		gl.ClearColor(0, 0, 0, 0)
		gl.Clear(gl.COLOR_BUFFER_BIT)

        gl.ActiveTexture(gl.TEXTURE0)

        // player update
        {
            using player

            change_state :: proc(using entity: ^Entity, new_state: Entity_State) {
                state = new_state
                frame_idx = 0
                tick = 0
                vel = {}
            }

            if .Pressed in keys[.One] {
                change_state(&player, .Free)
            }
            if .Pressed in keys[.Two] {
                change_state(&player, .Pop)
            }
            if .Pressed in keys[.Three] {
                change_state(&player, .Respawn)
            }

            switch state {
                case .Respawn:
                    animation_completed := advance_frame_idx(&player, dt, BUBBLE_FRAME_TIME, BUBBLE_FRAME_COUNT)
                    if animation_completed {
                        change_state(&player, .Free)
                    }

                case .Free:
                    advance_frame_idx(&player, dt, BUBBLE_FRAME_TIME, BUBBLE_FRAME_COUNT)

                    if .Down in keys[.Left] {
                        vel.x -= PLAYER_ACC
                    }
                    if .Down in keys[.Right] {
                        vel.x += PLAYER_ACC
                    }
                    if .Down in keys[.Down] {
                        vel.y += PLAYER_ACC
                    }
                    if .Down in keys[.Up] {
                        vel.y -= PLAYER_ACC
                    }
                    pos += vel
                    if x < 0 || x > GAME_WIDTH-32 || y < 0 || y > GAME_HEIGHT-32 {
                        change_state(&player, .Pop)
                    }

                case .Pop:
                    animation_completed := advance_frame_idx(&player, dt, BUBBLE_FRAME_TIME, BUBBLE_FRAME_COUNT)
                    if animation_completed {
                        change_state(&player, .Respawn)
                        pos = {GAME_WIDTH/2, GAME_HEIGHT/2} // TODO
                    }
            }

            gl.Uniform1i(gl.GetUniformLocation(shader, "frame_idx"), frame_idx)

            when ODIN_DEBUG {
                if .Pressed in keys[.R] {
                    change_state(&player, .Pop)
                }
            }

            gl.Uniform2fv(gl.GetUniformLocation(shader, "pos"), 1, raw_data(&player.pos))

            texture_index: int
            switch state {
                case .Free: 
                    texture_index = 0
                    gl.Uniform1i(gl.GetUniformLocation(shader, "frame_count"), BUBBLE_FRAME_COUNT)
                case .Pop: 
                    texture_index = 1
                    gl.Uniform1i(gl.GetUniformLocation(shader, "frame_count"), BUBBLE_FRAME_COUNT)
                case .Respawn: 
                    texture_index = 2
                    gl.Uniform1i(gl.GetUniformLocation(shader, "frame_count"), BUBBLE_FRAME_COUNT)
            }
            gl.BindTexture(gl.TEXTURE_2D, textures[texture_index]);
            gl.DrawArrays(gl.TRIANGLES, 0, 6)
        }

        // draw spikes
        // {
        //     gl.BindTexture(gl.TEXTURE_2D, textures[3]);
        //     gl.Uniform1i(gl.GetUniformLocation(shader, "frame_count"), 1)
        //     gl.Uniform1i(gl.GetUniformLocation(shader, "frame_idx"), 0)
        //     spike_pos: [2]f32
        //     for b in level {
        //         if b == 'S' {
        //             gl.Uniform2fv(gl.GetUniformLocation(shader, "pos"), 1, raw_data(&spike_pos))
        //             gl.DrawArrays(gl.TRIANGLES, 0, 6)
        //         } else if b == '\n' {
        //             spike_pos.x = 0
        //             spike_pos.y += 32
        //         } else {
        //             spike_pos.x += 32
        //         }
        //     }
        // }

		app.gl_swap_buffers(app_ctx)
	}
}